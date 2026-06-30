-- ============================================================
-- HRT DASHBOARD — SUPABASE SCHEMA v2.1
-- Run in: https://supabase.com/dashboard/project/lnxhksnvcewtpwkaghrh/sql
-- Drop existing tables first if rebuilding from scratch.
-- ============================================================

-- ============================================================
-- 1. COMPOUND LIBRARY (global, no user_id)
--    Reference table for all compounds. Powers calculators,
--    charts, and the log form.
-- ============================================================
CREATE TABLE compound_library (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name                    TEXT NOT NULL,               -- "Testosterone"
  ester                   TEXT,                        -- "Cypionate" (null for orals/peptides)
  full_name               TEXT NOT NULL,               -- "Testosterone Cypionate"
  code                    TEXT NOT NULL UNIQUE,        -- "TC"

  -- Classification
  category                TEXT NOT NULL,               -- "injectable_anabolic"|"oral_anabolic"|"gh"|"insulin"|"glp1"|"peptide"|"ancillary"|"fat_burner"|"supplement"|"research"
  class                   TEXT NOT NULL,               -- "testosterone"|"dht_derivative"|"19nor"|"17aa"|"gh"|"insulin"|"glp1_agonist"|"peptide"|"ai"|"serm"|"arb"|"fat_burner"
  cycle_role              TEXT,                        -- "base"|"primary_anabolic"|"secondary_anabolic"|"oral_kickstart"|"peptide_gh"|"insulin"|"support"
  route                   TEXT NOT NULL,               -- "im"|"subq"|"oral"|"transdermal"|"sublingual"
  unit                    TEXT NOT NULL,               -- "mg"|"IU"|"mcg"

  -- Pharmacokinetics (for blood level simulation)
  half_life_days          DECIMAL(6,2),                -- NULL = unknown (peptides), calculator disabled
  active_fraction         DECIMAL(4,3),                -- 0.69 for TC (ester weight ratio); NULL for orals

  -- Pharmacology flags
  aromatizes              BOOLEAN DEFAULT FALSE,
  aromatizes_to           TEXT,                        -- "estradiol"|"methylestradiol"|NULL
  dht_conversion          BOOLEAN DEFAULT FALSE,
  progestogenic           BOOLEAN DEFAULT FALSE,

  -- Goal & risk metadata
  goal_tags               TEXT[],                      -- '{"hypertrophy","fat_loss","trt","soft_tissue_repair",...}'
  risk_level              TEXT CHECK (risk_level IN ('low','moderate','high','very_high')),
  risk_organs             TEXT[],                      -- '{"liver","cardiovascular","kidney","neurological"}'
  contraindications       TEXT[],                      -- '{"prostate_cancer","elevated_hematocrit"}'

  -- Calculator fields
  concentration_mg_per_ml DECIMAL(8,2),                -- 200 for TC (null for orals/peptides)
  concentration_iu_per_ml DECIMAL(8,2),                -- 100 for insulins
  is_reconstituted        BOOLEAN NOT NULL DEFAULT FALSE, -- TRUE for GH, GLP-1, peptides
  vial_amount_default     DECIMAL(8,2),                -- default vial size (mg or IU)
  syringe_size_ml         DECIMAL(4,2),                -- 1.0 for IM, 0.3 for SubQ/insulin

  -- Dosing guidance
  dose_min                DECIMAL(10,3),               -- minimum typical dose (per injection)
  dose_max                DECIMAL(10,3),               -- maximum typical dose (per injection)
  loading_dose            DECIMAL(10,3),               -- loading phase dose (TB-500, GLP-1s)
  loading_weeks           SMALLINT,                    -- weeks at loading dose
  maintenance_dose        DECIMAL(10,3),               -- maintenance phase dose
  max_duration_weeks      SMALLINT,                    -- NULL = no limit; 4-6 for hepatotoxic orals
  oral_timing             TEXT,                        -- "pre_workout"|"morning"|"split"|NULL

  -- Scheduling
  frequency_default       TEXT,                        -- "E3.5D"|"ED"|"QW"|"E2D"|"EOD"
  frequency_interval_days DECIMAL(5,2),                -- 3.5|1.0|7.0|2.33|2.0

  -- Display
  color_hex               TEXT DEFAULT '#6b7280',
  sort_order              INTEGER DEFAULT 99,
  active                  BOOLEAN NOT NULL DEFAULT TRUE,
  notes                   TEXT,
  created_at              TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 2. INJECTION SITES (fixed list, global)
-- ============================================================
CREATE TABLE injection_sites (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL UNIQUE,   -- "Left Glute"
  code        TEXT NOT NULL UNIQUE,   -- "LG"
  region      TEXT NOT NULL,          -- "Glute"|"Delt"|"VG"|"Belly"|"Quad"|"Thigh"
  side        TEXT,                   -- "Left"|"Right"|NULL for bilateral
  route       TEXT NOT NULL,          -- "IM"|"SubQ"
  notes       TEXT,                   -- rotation tips, nerve avoidance notes
  sort_order  INTEGER DEFAULT 99
);

-- ============================================================
-- 3. PROFILES (auto-created on signup)
-- ============================================================
CREATE TABLE IF NOT EXISTS profiles (
  id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email      TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 4. USER VIALS (per user — reconstituted compounds in use)
--    Tracks actual vials: bac water added, concentration,
--    doses remaining, expiry. Used by peptide/GH/GLP calculator.
-- ============================================================
CREATE TABLE user_vials (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                 UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  compound_id             UUID NOT NULL REFERENCES compound_library(id),
  vial_amount_mg          DECIMAL(8,2) NOT NULL,       -- e.g. 5 (mg) or 10 (IU)
  bac_water_added_ml      DECIMAL(6,2),                -- e.g. 2.0 mL
  concentration_per_ml    DECIMAL(10,4),               -- computed: vial_amount / bac_water
  opened_date             DATE NOT NULL DEFAULT CURRENT_DATE,
  expiry_date             DATE,                        -- opened_date + 28 days for most peptides
  doses_per_vial          INTEGER,                     -- vial_amount / dose_per_use
  doses_used              INTEGER DEFAULT 0,
  doses_remaining         INTEGER,                     -- doses_per_vial - doses_used
  active                  BOOLEAN NOT NULL DEFAULT TRUE,
  notes                   TEXT,
  created_at              TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 5. PROTOCOLS (per user — named phases/cycles)
-- ============================================================
CREATE TABLE protocols (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name             TEXT NOT NULL,        -- "2026 Prep Cycle" | "Q1 Cruise"
  phase            TEXT NOT NULL,        -- "bulk"|"cut"|"rebound"|"cruise"
  experience_level TEXT CHECK (experience_level IN ('beginner','intermediate','advanced')),
  caloric_strategy TEXT CHECK (caloric_strategy IN ('surplus','deficit','maintenance')),
  goal             TEXT,                 -- "competition prep"|"recomp"|"trt"|"injury recovery"
  start_date       DATE NOT NULL,
  end_date         DATE,                 -- NULL = currently active
  weeks_out        SMALLINT,            -- competition countdown (NULL if not a prep)
  notes            TEXT,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 6. PROTOCOL COMPOUNDS (child of protocols)
--    Defines which compounds are in a protocol and their role.
--    Actual weekly doses are stored in protocol_compound_segments.
-- ============================================================
CREATE TABLE protocol_compounds (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  protocol_id             UUID NOT NULL REFERENCES protocols(id) ON DELETE CASCADE,
  compound_id             UUID NOT NULL REFERENCES compound_library(id),
  role_in_protocol        TEXT,          -- "base"|"primary_anabolic"|"secondary_anabolic"|"oral_kickstart"|"support"
  planned_weekly_dose     DECIMAL(10,3), -- baseline planned dose (mg/week or IU/day)
  frequency               TEXT NOT NULL, -- "E3.5D"|"ED"|"QW"|"E2D"|"EOD"
  frequency_interval_days DECIMAL(5,2) NOT NULL,
  max_duration_weeks      SMALLINT,      -- override compound default for this protocol
  oral_timing             TEXT,          -- "pre_workout"|"morning"|"split"
  preferred_site_id       UUID REFERENCES injection_sites(id),
  notes                   TEXT
);

-- ============================================================
-- 7. PROTOCOL COMPOUND SEGMENTS
--    Dose changes within a protocol by week.
--    One row per dose segment (flat, stepped, or ramped).
--    Handles: flat doses, mid-cycle additions, escalations, DROPs.
--
--    Examples from real cycles:
--      Tren added at week 9: week_start=9, week_end=2, dose=175
--      Clen ramp: 20mcg(wk9), 40mcg(wk8), 60mcg(wk7)... = multiple rows
--      Hard DROP: dose=NULL means compound not running that week
--      Anavar doubles: week_start=6,dose=25 + week_start=2,dose=50
-- ============================================================
CREATE TABLE protocol_compound_segments (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  protocol_compound_id UUID NOT NULL REFERENCES protocol_compounds(id) ON DELETE CASCADE,
  week_start           SMALLINT NOT NULL,  -- weeks out from show/end (16, 9, 4...)
  week_end             SMALLINT NOT NULL,  -- inclusive end week
  dose                 DECIMAL(10,3),      -- NULL = compound dropped/not running
  dose_unit            TEXT,              -- "mg"|"IU"|"mcg" (inherits from compound if NULL)
  dose_frequency       TEXT,              -- override frequency for this segment if different
  notes                TEXT               -- "split AM/PM", "pre-workout", "EOD"
);

-- ============================================================
-- 8. ADMINISTRATION LOG (per user — every dose event)
--    One row per compound per administration.
-- ============================================================
CREATE TABLE administration_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date            DATE NOT NULL,
  time_of_day     TIME,                   -- e.g. 08:00
  compound_id     UUID NOT NULL REFERENCES compound_library(id),
  vial_id         UUID REFERENCES user_vials(id),
  dose            DECIMAL(10,3) NOT NULL,
  unit            TEXT NOT NULL,
  volume_ml       DECIMAL(6,3),           -- IM/SubQ only; auto-calc or manual override
  site_id         UUID REFERENCES injection_sites(id),
  site_note       TEXT,
  protocol_id     UUID REFERENCES protocols(id),
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 9. DAILY METRICS (per user — once per day)
-- ============================================================
CREATE TABLE daily_logs (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date                DATE NOT NULL,
  weight_lbs          DECIMAL(5,1),
  fasting_glucose     INTEGER,            -- mg/dL
  bp_systolic         INTEGER,
  bp_diastolic        INTEGER,
  calories            INTEGER,
  protein_g           INTEGER,
  mood                SMALLINT CHECK (mood BETWEEN 1 AND 10),
  energy              SMALLINT CHECK (energy BETWEEN 1 AND 10),
  libido              SMALLINT CHECK (libido BETWEEN 1 AND 10),
  notes               TEXT,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, date)
);

-- ============================================================
-- 10. LABS (per user — one row per marker per draw)
-- ============================================================
CREATE TABLE labs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  draw_date       DATE NOT NULL,
  lab_name        TEXT,                   -- "LabCorp"|"Quest"
  trough_hours    DECIMAL(5,1),           -- hours since last injection
  marker          TEXT NOT NULL,          -- "Total Testosterone"|"Hematocrit"|"E2"
  result          DECIMAL(10,3) NOT NULL,
  unit            TEXT NOT NULL,          -- "ng/dL"|"%"|"pg/mL"
  ref_low         DECIMAL(10,3),
  ref_high        DECIMAL(10,3),
  flag            TEXT,                   -- "H"|"L"|"N"
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 10b. LAB_RESULTS (per user — wide/panel format, one row per draw date)
--      Used by the HRT Tracker dashboard app for manual panel entry.
-- ============================================================
CREATE TABLE lab_results (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  drawn_at              DATE NOT NULL,
  total_testosterone    DECIMAL(10,2),   -- ng/dL
  free_testosterone     DECIMAL(10,3),   -- pg/mL
  estradiol             DECIMAL(10,2),   -- pg/mL (sensitive E2)
  shbg                  DECIMAL(10,2),   -- nmol/L
  hematocrit            DECIMAL(5,2),    -- %
  hemoglobin            DECIMAL(5,2),    -- g/dL
  psa                   DECIMAL(6,3),    -- ng/mL
  lh                    DECIMAL(6,2),    -- mIU/mL
  fsh                   DECIMAL(6,2),    -- mIU/mL
  ast                   DECIMAL(6,1),    -- U/L
  alt                   DECIMAL(6,1),    -- U/L
  notes                 TEXT,
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, drawn_at)
);

-- ============================================================
-- 11. HEALTHKIT DAILY (per user — Apple Health sync)
-- ============================================================
CREATE TABLE healthkit_daily (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date                DATE NOT NULL,
  weight_lbs          DECIMAL(5,1),
  body_fat_pct        DECIMAL(4,1),
  lean_mass_lbs       DECIMAL(5,1),
  hrv_ms              DECIMAL(6,1),
  resting_hr          INTEGER,
  hr_min              INTEGER,
  hr_avg              INTEGER,
  hr_max              INTEGER,
  sleep_total_hr      DECIMAL(4,2),
  sleep_deep_hr       DECIMAL(4,2),
  sleep_rem_hr        DECIMAL(4,2),
  steps               INTEGER,
  active_energy_kcal  DECIMAL(7,1),
  exercise_min        INTEGER,
  bp_systolic         INTEGER,
  bp_diastolic        INTEGER,
  spo2_pct            DECIMAL(4,1),
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, date)
);

-- ============================================================
-- 12. WORKOUTS — Hevy placeholder
-- ============================================================
CREATE TABLE workouts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date            DATE NOT NULL,
  source          TEXT DEFAULT 'manual',  -- "hevy"|"manual"
  external_id     TEXT,                   -- Hevy workout ID
  title           TEXT,
  duration_min    INTEGER,
  volume_total_kg DECIMAL(10,2),
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE workout_sets (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workout_id      UUID NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
  exercise_name   TEXT NOT NULL,
  set_number      SMALLINT NOT NULL,
  reps            SMALLINT,
  weight_kg       DECIMAL(6,2),
  rpe             DECIMAL(3,1),
  notes           TEXT
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX idx_admin_log_user_date       ON administration_log (user_id, date DESC);
CREATE INDEX idx_admin_log_compound        ON administration_log (compound_id);
CREATE INDEX idx_daily_logs_user_date   ON daily_logs (user_id, date DESC);
CREATE INDEX idx_labs_user_date            ON labs (user_id, draw_date DESC);
CREATE INDEX idx_labs_marker               ON labs (user_id, marker);
CREATE INDEX idx_protocols_user            ON protocols (user_id, start_date DESC);
CREATE INDEX idx_healthkit_user_date       ON healthkit_daily (user_id, date DESC);
CREATE INDEX idx_user_vials_user           ON user_vials (user_id, active);
CREATE INDEX idx_workouts_user_date        ON workouts (user_id, date DESC);
CREATE INDEX idx_protocol_compounds        ON protocol_compounds (protocol_id);
CREATE INDEX idx_protocol_segments         ON protocol_compound_segments (protocol_compound_id, week_start DESC);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
ALTER TABLE profiles                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_vials                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE administration_log           ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_logs                ENABLE ROW LEVEL SECURITY;
ALTER TABLE labs                         ENABLE ROW LEVEL SECURITY;
ALTER TABLE protocols                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE protocol_compounds           ENABLE ROW LEVEL SECURITY;
ALTER TABLE protocol_compound_segments   ENABLE ROW LEVEL SECURITY;
ALTER TABLE healthkit_daily              ENABLE ROW LEVEL SECURITY;
ALTER TABLE workouts                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_sets                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE compound_library             ENABLE ROW LEVEL SECURITY;
ALTER TABLE injection_sites              ENABLE ROW LEVEL SECURITY;
ALTER TABLE lab_results                  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users own profile"
  ON profiles FOR ALL USING (auth.uid() = id);
CREATE POLICY "Users own vials"
  ON user_vials FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users own admin_log"
  ON administration_log FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users own daily_logs"
  ON daily_logs FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users own labs"
  ON labs FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users own lab_results"
  ON lab_results FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users own protocols"
  ON protocols FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users own healthkit"
  ON healthkit_daily FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users own workouts"
  ON workouts FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users own workout_sets"
  ON workout_sets FOR ALL USING (
    workout_id IN (SELECT id FROM workouts WHERE user_id = auth.uid())
  );
CREATE POLICY "Users own protocol_compounds"
  ON protocol_compounds FOR ALL USING (
    protocol_id IN (SELECT id FROM protocols WHERE user_id = auth.uid())
  );
CREATE POLICY "Users own protocol_segments"
  ON protocol_compound_segments FOR ALL USING (
    protocol_compound_id IN (
      SELECT pc.id FROM protocol_compounds pc
      JOIN protocols p ON pc.protocol_id = p.id
      WHERE p.user_id = auth.uid()
    )
  );
-- compound_library and injection_sites are public read
CREATE POLICY "Public read compound_library"
  ON compound_library FOR SELECT USING (true);
CREATE POLICY "Public read injection_sites"
  ON injection_sites FOR SELECT USING (true);

-- ============================================================
-- AUTO-CREATE PROFILE ON SIGNUP
-- ============================================================
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, email) VALUES (NEW.id, NEW.email);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ============================================================
-- SEED: INJECTION SITES
-- ============================================================
INSERT INTO injection_sites (name, code, region, side, route, notes, sort_order) VALUES
  ('Left Glute',    'LG',   'Glute', 'Left',  'IM',   'Upper outer quadrant. Most common IM site.', 1),
  ('Right Glute',   'RG',   'Glute', 'Right', 'IM',   'Upper outer quadrant. Most common IM site.', 2),
  ('Left Delt',     'LD',   'Delt',  'Left',  'IM',   'Lateral head. Max 1mL volume recommended.',  3),
  ('Right Delt',    'RD',   'Delt',  'Right', 'IM',   'Lateral head. Max 1mL volume recommended.',  4),
  ('Left VG',       'LVG',  'VG',    'Left',  'IM',   'Ventroglute. Safest IM — no major nerves.',  5),
  ('Right VG',      'RVG',  'VG',    'Right', 'IM',   'Ventroglute. Safest IM — no major nerves.',  6),
  ('Left Quad',     'LQ',   'Quad',  'Left',  'IM',   'Vastus lateralis. Outer sweep only.',        7),
  ('Right Quad',    'RQ',   'Quad',  'Right', 'IM',   'Vastus lateralis. Outer sweep only.',        8),
  ('Belly',         'BL',   'Belly', NULL,    'SubQ', 'Rotate sites. 1–2 inches from navel.',       9),
  ('Left Thigh',    'LT',   'Thigh', 'Left',  'SubQ', 'SubQ pinch. Common for GLP-1/peptides.',    10),
  ('Right Thigh',   'RT',   'Thigh', 'Right', 'SubQ', 'SubQ pinch. Common for GLP-1/peptides.',    11);

-- ============================================================
-- SEED: COMPOUND LIBRARY
-- Columns: name, ester, full_name, code, category, class,
--   cycle_role, route, unit, half_life_days, active_fraction,
--   aromatizes, aromatizes_to, dht_conversion, progestogenic,
--   goal_tags, risk_level, risk_organs, contraindications,
--   concentration_mg_per_ml, concentration_iu_per_ml,
--   is_reconstituted, vial_amount_default, syringe_size_ml,
--   dose_min, dose_max, loading_dose, loading_weeks, maintenance_dose,
--   max_duration_weeks, oral_timing,
--   frequency_default, frequency_interval_days,
--   color_hex, sort_order, notes
-- ============================================================

-- ── INJECTABLE ANDROGENS ───────────────────────────────────────────────────

INSERT INTO compound_library (
  name, ester, full_name, code, category, class, cycle_role, route, unit,
  half_life_days, active_fraction,
  aromatizes, aromatizes_to, dht_conversion, progestogenic,
  goal_tags, risk_level, risk_organs, contraindications,
  concentration_mg_per_ml, is_reconstituted, syringe_size_ml,
  dose_min, dose_max,
  frequency_default, frequency_interval_days,
  color_hex, sort_order, notes
) VALUES
('Testosterone', 'Cypionate',  'Testosterone Cypionate',  'TC',
 'injectable_anabolic', 'testosterone', 'base', 'im', 'mg',
 8.0, 0.69,
 TRUE, 'estradiol', TRUE, FALSE,
 ARRAY['hypertrophy','trt','hrt','body_composition','strength'],
 'moderate', ARRAY['cardiovascular','prostate'], ARRAY['prostate_cancer','elevated_hematocrit','heart_failure'],
 200, FALSE, 1.0,
 100, 400,
 'E3.5D', 3.5,
 '#f59e0b', 1, 'TRT standard. TC and TE are interchangeable; prefer TC for US, TE for Europe.'),

('Testosterone', 'Enanthate',  'Testosterone Enanthate',  'TE',
 'injectable_anabolic', 'testosterone', 'base', 'im', 'mg',
 5.0, 0.72,
 TRUE, 'estradiol', TRUE, FALSE,
 ARRAY['hypertrophy','trt','hrt','body_composition','strength'],
 'moderate', ARRAY['cardiovascular','prostate'], ARRAY['prostate_cancer','elevated_hematocrit','heart_failure'],
 250, FALSE, 1.0,
 100, 500,
 'E3.5D', 3.5,
 '#fbbf24', 2, 'Most common injectable for blast cycles. Switch to Prop last half of prep for dosing flexibility.'),

('Testosterone', 'Propionate', 'Testosterone Propionate', 'TP',
 'injectable_anabolic', 'testosterone', 'base', 'im', 'mg',
 2.0, 0.80,
 TRUE, 'estradiol', TRUE, FALSE,
 ARRAY['hypertrophy','trt','body_composition','fat_loss'],
 'moderate', ARRAY['cardiovascular','prostate'], ARRAY['prostate_cancer','elevated_hematocrit'],
 100, FALSE, 1.0,
 50, 200,
 'EOD', 2.0,
 '#f59e0b', 3, 'Short ester — preferred for end of prep cuts. More injection frequency but easier to drop pre-show.'),

('Masteron', 'Enanthate',  'Masteron Enanthate',  'MastE',
 'injectable_anabolic', 'dht_derivative', 'primary_anabolic', 'im', 'mg',
 5.0, 0.72,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['body_composition','fat_loss','hypertrophy'],
 'low', ARRAY['lipids'], ARRAY[],
 200, FALSE, 1.0,
 200, 600,
 'E3.5D', 3.5,
 '#22d3ee', 4, 'DHT derivative — drying, hardening effect. Anti-estrogenic at high doses. Safe side effect profile.'),

('Masteron', 'Propionate', 'Masteron Propionate', 'MastP',
 'injectable_anabolic', 'dht_derivative', 'primary_anabolic', 'im', 'mg',
 2.0, 0.80,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['body_composition','fat_loss'],
 'low', ARRAY['lipids'], ARRAY[],
 100, FALSE, 1.0,
 100, 400,
 'EOD', 2.0,
 '#06b6d4', 5, 'Short ester Masteron. Used in final prep weeks.'),

('Primobolan', 'Enanthate',  'Primobolan Enanthate',  'PrimoE',
 'injectable_anabolic', 'dht_derivative', 'primary_anabolic', 'im', 'mg',
 10.0, 0.65,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['hypertrophy','body_composition','fat_loss'],
 'low', ARRAY['lipids'], ARRAY[],
 100, FALSE, 1.0,
 200, 600,
 'E3.5D', 3.5,
 '#d97706', 6, 'Safest injectable anabolic. Best primary anabolic for most users. Run at 70-80% of test dose.'),

('Boldenone', 'Undecylenate', 'Boldenone Undecylenate (Equipoise)', 'EQ',
 'injectable_anabolic', 'testosterone', 'primary_anabolic', 'im', 'mg',
 14.0, 0.61,
 TRUE, 'estradiol', FALSE, FALSE,
 ARRAY['hypertrophy','body_composition'],
 'moderate', ARRAY['cardiovascular'], ARRAY['elevated_hematocrit'],
 300, FALSE, 1.0,
 200, 600,
 'E3.5D', 3.5,
 '#f97316', 7, 'Structurally similar to DBOL but injectable. Elevates RBC and BP. Run at 70-80% of test dose.'),

('Nandrolone', 'Decanoate',   'Nandrolone Decanoate (Deca)',  'Deca',
 'injectable_anabolic', '19nor', 'secondary_anabolic', 'im', 'mg',
 15.0, 0.62,
 TRUE, 'estradiol', FALSE, TRUE,
 ARRAY['hypertrophy','bone_joint_health'],
 'moderate', ARRAY['cardiovascular','neurological'], ARRAY['mental_health_history'],
 250, FALSE, 1.0,
 200, 400,
 'QW', 7.0,
 '#fb923c', 8, 'Mildly neuro and cardiotoxic. Run at 20-30% of test dose. Progestogenic — use cabergoline if needed.'),

('Trenbolone', 'Acetate',     'Trenbolone Acetate',   'TrenA',
 'injectable_anabolic', '19nor', 'secondary_anabolic', 'im', 'mg',
 2.0, 0.87,
 FALSE, NULL, FALSE, TRUE,
 ARRAY['body_composition','strength','fat_loss','glucocorticoid_suppression'],
 'very_high', ARRAY['kidney','cardiovascular','neurological'], ARRAY['kidney_disease','mental_health_history','cardiovascular_disease'],
 100, FALSE, 1.0,
 100, 400,
 'EOD', 2.0,
 '#f87171', 9, 'Most potent anabolic per mg. Tren cough possible if injected into vein. Does not aromatize but progestogenic — gyno risk still exists. Binds glucocorticoid receptors (cortisol suppression).'),

('Trenbolone', 'Enanthate',   'Trenbolone Enanthate',  'TrenE',
 'injectable_anabolic', '19nor', 'secondary_anabolic', 'im', 'mg',
 7.0, 0.72,
 FALSE, NULL, FALSE, TRUE,
 ARRAY['body_composition','strength','fat_loss','glucocorticoid_suppression'],
 'very_high', ARRAY['kidney','cardiovascular','neurological'], ARRAY['kidney_disease','mental_health_history','cardiovascular_disease'],
 200, FALSE, 1.0,
 200, 400,
 'E3.5D', 3.5,
 '#ef4444', 10, 'Long ester Tren. Harder to manage sides due to long half-life — TrenA preferred for first Tren cycle.'),

('Trenbolone', 'Hexahydrobenzylcarbonate', 'Trenbolone Hexahydrobenzylcarbonate (Parabolan)', 'TrenHex',
 'injectable_anabolic', '19nor', 'secondary_anabolic', 'im', 'mg',
 14.0, 0.70,
 FALSE, NULL, FALSE, TRUE,
 ARRAY['body_composition','strength'],
 'very_high', ARRAY['kidney','cardiovascular','neurological'], ARRAY['kidney_disease','mental_health_history'],
 76, FALSE, 1.0,
 150, 300,
 'E3.5D', 3.5,
 '#dc2626', 11, 'Parabolan — human-grade Tren. Longest ester.'),

-- ── ORAL ANABOLICS ────────────────────────────────────────────────────────

('Methandrostenolone', NULL, 'Dianabol (DBOL)',  'DBOL',
 'oral_anabolic', '17aa', 'oral_kickstart', 'oral', 'mg',
 0.25, 1.0,
 TRUE, 'methylestradiol', FALSE, FALSE,
 ARRAY['hypertrophy','strength'],
 'high', ARRAY['liver','cardiovascular'], ARRAY['liver_disease','elevated_bp'],
 NULL, FALSE, NULL,
 20, 100,
 NULL, NULL, NULL, NULL, NULL,
 6, 'pre_workout',
 'ED', 1.0,
 '#f97316', 20, 'Classic oral kickstart. Aromatizes to methylestradiol (more potent than estradiol) — standard AIs less effective. Anadrol or DBOL pre-workout for 4-6 weeks max.'),

('Oxandrolone', NULL, 'Anavar', 'Anavar',
 'oral_anabolic', '17aa', 'oral_kickstart', 'oral', 'mg',
 0.5, 1.0,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['body_composition','strength','fat_loss'],
 'moderate', ARRAY['liver','lipids'], ARRAY['liver_disease'],
 NULL, FALSE, NULL,
 25, 100,
 NULL, NULL, NULL, NULL, NULL,
 6, 'pre_workout',
 'ED', 1.0,
 '#34d399', 21, 'Mildest oral. Common for women and beginners. Winstrol or Anavar added last 4-6 weeks of cut for hardening.'),

('Stanozolol', NULL, 'Winstrol', 'Winny',
 'oral_anabolic', '17aa', 'oral_kickstart', 'oral', 'mg',
 0.33, 1.0,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['body_composition','strength','fat_loss'],
 'high', ARRAY['liver','lipids'], ARRAY['liver_disease','joint_issues'],
 NULL, FALSE, NULL,
 25, 100,
 NULL, NULL, NULL, NULL, NULL,
 6, 'pre_workout',
 'ED', 1.0,
 '#84cc16', 22, 'Drying compound. Joint pain common at high doses. Added last 4-6 weeks for hardening.'),

('Oxymetholone', NULL, 'Anadrol', 'Adrol',
 'oral_anabolic', '17aa', 'oral_kickstart', 'oral', 'mg',
 0.5, 1.0,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['hypertrophy','strength'],
 'high', ARRAY['liver','lipids','cardiovascular'], ARRAY['liver_disease'],
 NULL, FALSE, NULL,
 25, 100,
 NULL, NULL, NULL, NULL, NULL,
 6, 'pre_workout',
 'ED', 1.0,
 '#f97316', 23, 'Strongest oral for mass and strength. Does not directly aromatize but causes significant estrogen-like sides via unknown mechanism.'),

('Fluoxymesterone', NULL, 'Halotestin', 'Halo',
 'oral_anabolic', '17aa', 'oral_kickstart', 'oral', 'mg',
 0.4, 1.0,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['strength','body_composition'],
 'very_high', ARRAY['liver','lipids'], ARRAY['liver_disease','mental_health_history'],
 NULL, FALSE, NULL,
 5, 20,
 NULL, NULL, NULL, NULL, NULL,
 3, 'pre_workout',
 'ED', 1.0,
 '#dc2626', 24, 'Extreme aggression and strength. Hepatotoxic and psychologically harsh. Last 2-3 weeks only pre-competition.'),

('Mesterolone', NULL, 'Proviron', 'Proviron',
 'oral_anabolic', 'dht_derivative', 'support', 'oral', 'mg',
 0.5, 1.0,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['body_composition','estrogen_control'],
 'low', ARRAY['lipids'], ARRAY[],
 NULL, FALSE, NULL,
 25, 75,
 NULL, NULL, NULL, NULL, NULL,
 NULL, 'morning',
 'ED', 1.0,
 '#fbbf24', 25, 'DHT derivative. Mild anti-estrogenic effect. Safe side effect profile. Often used throughout cycle.'),

-- ── GROWTH HORMONE ────────────────────────────────────────────────────────

('Somatropin', NULL, 'UGL GH (Somatropin)', 'GH',
 'gh', 'gh', 'peptide_gh', 'subq', 'IU',
 0.2, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['hypertrophy','body_composition','bone_joint_health','fat_loss'],
 'moderate', ARRAY['cardiovascular'], ARRAY['active_cancer','diabetic_retinopathy'],
 NULL, TRUE, 0.3,
 2, 10,
 NULL, NULL, NULL, NULL, NULL,
 NULL, 'morning',
 'ED', 1.0,
 '#60a5fa', 30, 'Reconstitute with bac water. Split dose: half AM, half pre-PM workout. Performance effects at 5+ IU/day. 1mg = 3 IU.'),

-- ── INSULIN ───────────────────────────────────────────────────────────────

('Insulin Lispro',  NULL, 'Humalog',   'Humalog',
 'insulin', 'insulin', 'insulin', 'subq', 'IU',
 0.08, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['nutrient_uptake'],
 'very_high', ARRAY[],  ARRAY['hypoglycemia_history'],
 NULL, FALSE, 0.3,
 2, 15,
 NULL, NULL, NULL, NULL, NULL,
 NULL, NULL,
 'ED', 1.0,
 '#e879f9', 40, 'Fast-acting insulin. Advanced users only. HYPOGLYCEMIA RISK — always have fast carbs on hand. 100 IU = 1 mL.'),

('Insulin Aspart',  NULL, 'Novolog',   'Novolog',
 'insulin', 'insulin', 'insulin', 'subq', 'IU',
 0.08, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['nutrient_uptake'],
 'very_high', ARRAY[], ARRAY['hypoglycemia_history'],
 NULL, FALSE, 0.3,
 2, 15,
 NULL, NULL, NULL, NULL, NULL,
 NULL, NULL,
 'ED', 1.0,
 '#d946ef', 41, 'Fast-acting insulin. Advanced users only. HYPOGLYCEMIA RISK.'),

('Insulin Regular', NULL, 'Novolin R', 'NovR',
 'insulin', 'insulin', 'insulin', 'subq', 'IU',
 0.25, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['nutrient_uptake'],
 'very_high', ARRAY[], ARRAY['hypoglycemia_history'],
 NULL, FALSE, 0.3,
 2, 15,
 NULL, NULL, NULL, NULL, NULL,
 NULL, NULL,
 'ED', 1.0,
 '#c026d3', 42, 'Regular human insulin (slower onset than analogs). For improved nutrient uptake. High level competitors only.'),

-- ── GLP-1 AGONISTS (reconstituted) ───────────────────────────────────────

('Semaglutide', NULL, 'Semaglutide', 'Sema',
 'glp1', 'glp1_agonist', 'support', 'subq', 'mg',
 7.0, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['fat_loss','nutrient_uptake'],
 'low', ARRAY[], ARRAY['personal_or_family_history_medullary_thyroid_carcinoma'],
 NULL, TRUE, 0.3,
 0.25, 2.4,
 0.25, 4, 1.0,
 NULL, NULL,
 'QW', 7.0,
 '#34d399', 50, 'GLP-1 agonist. Titrate up: 0.25mg → 0.5mg → 1mg → 2.4mg over 4-week intervals. Reconstitute with bac water.'),

('Tirzepatide', NULL, 'Tirzepatide', 'Tirz',
 'glp1', 'glp1_agonist', 'support', 'subq', 'mg',
 5.0, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['fat_loss','nutrient_uptake'],
 'low', ARRAY[], ARRAY['personal_or_family_history_medullary_thyroid_carcinoma'],
 NULL, TRUE, 0.3,
 2.5, 15.0,
 2.5, 4, 5.0,
 NULL, NULL,
 'QW', 7.0,
 '#6ee7b7', 51, 'GLP-1/GIP dual agonist. Titrate: 2.5mg → 5mg → 7.5mg → 10mg → 15mg. Reconstitute with bac water.'),

('Retatrutide', NULL, 'Retatrutide', 'Reta',
 'glp1', 'glp1_agonist', 'support', 'subq', 'mg',
 6.0, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['fat_loss','nutrient_uptake'],
 'low', ARRAY[], ARRAY[],
 NULL, TRUE, 0.3,
 1.0, 12.0,
 1.0, 4, 4.0,
 NULL, NULL,
 'QW', 7.0,
 '#a7f3d0', 52, 'Triple GLP-1/GIP/Glucagon agonist. Most potent fat loss agent. Titrate slowly. Reconstitute with bac water.'),

-- ── PEPTIDES (reconstituted) ──────────────────────────────────────────────

('BPC-157', NULL, 'BPC-157 (Body Protection Compound)', 'BPC',
 'peptide', 'peptide', 'support', 'subq', 'mcg',
 NULL, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['soft_tissue_repair','anti_inflammatory','gi_protection','neuroprotection'],
 'low', ARRAY[], ARRAY[],
 NULL, TRUE, 0.3,
 200, 500,
 NULL, NULL, NULL,
 4, NULL,
 'ED', 1.0,
 '#f87171', 60, 'Pentadecapeptide. Half-life unknown — blood level calculator disabled. Inject near injury site for targeted healing. Oral route effective for GI benefits. 200-500mcg/day injectable; 500-1000mcg/day oral.'),

('TB-500', NULL, 'TB-500 (Thymosin Beta-4)', 'TB500',
 'peptide', 'peptide', 'support', 'subq', 'mg',
 NULL, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['soft_tissue_repair','anti_inflammatory'],
 'low', ARRAY[], ARRAY[],
 NULL, TRUE, 0.3,
 2.0, 8.0,
 6.0, 6, 2.0,
 NULL, NULL,
 'E3.5D', 3.5,
 '#fca5a5', 61, 'Loading phase: 4-8mg/week x 4-6 weeks. Maintenance: 2-4mg/week. Reconstitute with bac water.'),

('CJC-1295', NULL, 'CJC-1295 (w/ DAC)', 'CJC',
 'peptide', 'peptide', 'support', 'subq', 'mcg',
 8.0, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['hypertrophy','fat_loss','bone_joint_health'],
 'low', ARRAY[], ARRAY[],
 NULL, TRUE, 0.3,
 100, 500,
 NULL, NULL, NULL,
 NULL, NULL,
 'E3D', 3.0,
 '#f9a8d4', 62, 'GHRH analog. Stack with Ipamorelin for synergistic GH pulse.'),

('Ipamorelin', NULL, 'Ipamorelin', 'Ipa',
 'peptide', 'peptide', 'support', 'subq', 'mcg',
 0.1, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['hypertrophy','fat_loss','bone_joint_health'],
 'low', ARRAY[], ARRAY[],
 NULL, TRUE, 0.3,
 100, 300,
 NULL, NULL, NULL,
 NULL, NULL,
 'ED', 1.0,
 '#fbcfe8', 63, 'Selective GHRP. Minimal cortisol/prolactin increase. Stack with CJC-1295.'),

-- ── ANCILLARIES ───────────────────────────────────────────────────────────

('Anastrozole', NULL, 'Anastrozole (Arimidex)', 'Adex',
 'ancillary', 'ai', 'support', 'oral', 'mg',
 2.0, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['estrogen_control'],
 'low', ARRAY['lipids','joint','bone'], ARRAY[],
 NULL, FALSE, NULL,
 0.25, 1.0,
 NULL, NULL, NULL,
 NULL, NULL,
 'EOD', 2.0,
 '#94a3b8', 70, 'Most common AI. Standard protocol: 0.5mg EOD wks 16-8, 0.5mg ED wks 7-3, 1mg ED wks 2-0. Less effective on DBOL cycle (methylestradiol).'),

('Letrozole', NULL, 'Letrozole (Femara)', 'Letro',
 'ancillary', 'ai', 'support', 'oral', 'mg',
 2.0, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['estrogen_control'],
 'low', ARRAY['lipids','joint','bone'], ARRAY[],
 NULL, FALSE, NULL,
 0.25, 2.5,
 NULL, NULL, NULL,
 NULL, NULL,
 'EOD', 2.0,
 '#64748b', 71, 'Most potent AI. Use for gyno rescue or very high estrogen situations.'),

('Exemestane', NULL, 'Exemestane (Aromasin)', 'Exemest',
 'ancillary', 'ai', 'support', 'oral', 'mg',
 1.0, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['estrogen_control'],
 'low', ARRAY['lipids','joint','bone'], ARRAY[],
 NULL, FALSE, NULL,
 12.5, 25.0,
 NULL, NULL, NULL,
 NULL, NULL,
 'EOD', 2.0,
 '#475569', 72, 'Steroidal (suicidal) AI — permanently inactivates aromatase. Does not rebound estrogen. Slightly anabolic.'),

('Tamoxifen', NULL, 'Tamoxifen (Nolvadex)', 'Nolva',
 'ancillary', 'serm', 'support', 'oral', 'mg',
 5.0, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['estrogen_control'],
 'low', ARRAY['clotting','bone'], ARRAY[],
 NULL, FALSE, NULL,
 10, 40,
 NULL, NULL, NULL,
 NULL, NULL,
 'ED', 1.0,
 '#818cf8', 73, 'SERM — blocks estrogen at breast tissue. Preferred over AI on DBOL (methylestradiol) cycles. Also used in PCT.'),

('Cabergoline', NULL, 'Cabergoline', 'Caber',
 'ancillary', 'dopamine_agonist', 'support', 'oral', 'mg',
 3.0, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['estrogen_control'],
 'low', ARRAY[], ARRAY[],
 NULL, FALSE, NULL,
 0.25, 1.0,
 NULL, NULL, NULL,
 NULL, NULL,
 'E3.5D', 3.5,
 '#94a3b8', 74, 'Dopamine agonist — controls prolactin. Required when using progestogenic compounds (Deca, Tren).'),

('Telmisartan', NULL, 'Telmisartan', 'Telmi',
 'ancillary', 'arb', 'support', 'oral', 'mg',
 1.0, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['blood_pressure'],
 'low', ARRAY['hyperkalemia'], ARRAY[],
 NULL, FALSE, NULL,
 20, 80,
 NULL, NULL, NULL,
 NULL, NULL,
 'ED', 1.0,
 '#94a3b8', 75, 'ARB for blood pressure control. Preferred over ACE inhibitors (no cough). Common on high-dose cycles.'),

('Enclomiphene', NULL, 'Enclomiphene', 'Enclo',
 'ancillary', 'serm', 'support', 'oral', 'mg',
 1.5, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['trt','hrt'],
 'low', ARRAY[], ARRAY[],
 NULL, FALSE, NULL,
 12.5, 25.0,
 NULL, NULL, NULL,
 NULL, NULL,
 'ED', 1.0,
 '#94a3b8', 76, 'SERM — stimulates LH/FSH. Used to maintain fertility and natural production on TRT.'),

-- ── FAT BURNERS ───────────────────────────────────────────────────────────

('Clenbuterol', NULL, 'Clenbuterol', 'Clen',
 'fat_burner', 'beta2_agonist', 'support', 'oral', 'mcg',
 1.5, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['fat_loss'],
 'high', ARRAY['cardiovascular'], ARRAY['heart_disease','hypertension'],
 NULL, FALSE, NULL,
 20, 120,
 NULL, NULL, NULL,
 NULL, NULL,
 'ED', 1.0,
 '#fde68a', 80, 'Ramp up 20mcg/day each week. Standard prep protocol: wk9=20mcg, wk8=40, wk7=60, wk6=80, wk5-0=100mcg. 2 weeks on/off if using long-term.'),

('Cytomel', NULL, 'T3 (Cytomel)', 'T3',
 'fat_burner', 'thyroid', 'support', 'oral', 'mcg',
 0.75, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['fat_loss'],
 'high', ARRAY['thyroid'], ARRAY['hyperthyroidism','cardiac_arrhythmia'],
 NULL, FALSE, NULL,
 12.5, 50,
 NULL, NULL, NULL,
 NULL, NULL,
 'ED', 1.0,
 '#fcd34d', 81, 'Suppresses natural thyroid. Beginner: 25mcg wks 4-0. Advanced: 25mcg wk4, 50mcg wks 3-0. Taper down in rebound.'),

('Ephedrine', NULL, 'Bronkaid (Ephedrine 25mg)', 'Ephed',
 'fat_burner', 'sympathomimetic', 'support', 'oral', 'mg',
 0.25, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['fat_loss'],
 'high', ARRAY['cardiovascular'], ARRAY['heart_disease','hypertension','anxiety'],
 NULL, FALSE, NULL,
 25, 75,
 NULL, NULL, NULL,
 NULL, NULL,
 'ED', 1.0,
 '#fef08a', 82, 'ECA stack component. 25mg AM only wks 15-13, 25mg AM+PM from wk 12. Drop at rebound 2.'),

('Yohimbine', NULL, 'Yohimbine HCl', 'Yohim',
 'fat_burner', 'alpha2_antagonist', 'support', 'oral', 'mg',
 0.5, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['fat_loss'],
 'moderate', ARRAY['cardiovascular'], ARRAY['heart_disease','anxiety'],
 NULL, FALSE, NULL,
 2.5, 20,
 NULL, NULL, NULL,
 NULL, NULL,
 'ED', 1.0,
 '#fef3c7', 83, 'Alpha-2 antagonist. Stacked with caffeine in "Go Pills" (200mg caffeine + 5mg yohimbine).'),

-- ── SUPPLEMENTS / METABOLICS ──────────────────────────────────────────────

('Metformin', NULL, 'Metformin', 'Metf',
 'supplement', 'biguanide', 'support', 'oral', 'mg',
 1.0, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['nutrient_uptake'],
 'low', ARRAY[], ARRAY['kidney_disease'],
 NULL, FALSE, NULL,
 500, 2000,
 NULL, NULL, NULL,
 NULL, NULL,
 'ED', 1.0,
 '#a3e635', 90, 'Insulin sensitizer. Gastric distress and low glucose risk. Take with food.'),

('Berberine', NULL, 'Berberine HCl', 'Berb',
 'supplement', 'alkaloid', 'support', 'oral', 'mg',
 0.5, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['nutrient_uptake'],
 'low', ARRAY[], ARRAY[],
 NULL, FALSE, NULL,
 500, 1500,
 NULL, NULL, NULL,
 NULL, NULL,
 'ED', 1.0,
 '#86efac', 91, 'Natural insulin sensitizer. Often stacked with Metformin or used as alternative.'),

-- ── RESEARCH COMPOUNDS ────────────────────────────────────────────────────

('GW-501516', NULL, 'Cardarine (GW-501516)', 'GW501',
 'research', 'ppar_delta', 'support', 'oral', 'mg',
 0.8, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['fat_loss','body_composition'],
 'moderate', ARRAY[], ARRAY[],
 NULL, FALSE, NULL,
 10, 20,
 NULL, NULL, NULL,
 8, NULL,
 'ED', 1.0,
 '#a78bfa', 95, 'PPAR-delta agonist. Enhances fat oxidation and endurance. NOT a SARM. Animal studies showed tumor growth at high doses — use cautiously.'),

('YK-11', NULL, 'YK-11', 'YK11',
 'research', 'sarm_myostatin', 'support', 'oral', 'mg',
 0.5, NULL,
 FALSE, NULL, FALSE, FALSE,
 ARRAY['hypertrophy','strength'],
 'moderate', ARRAY['liver'], ARRAY[],
 NULL, FALSE, NULL,
 5, 15,
 NULL, NULL, NULL,
 8, NULL,
 'ED', 1.0,
 '#c084fc', 96, 'Steroidal SARM / myostatin inhibitor. Promotes muscle growth beyond genetic limit. Limited human data.');

-- lab_markers: EAV table for all blood lab values (replaces flat lab_results columns)
CREATE TABLE IF NOT EXISTS lab_markers (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid REFERENCES auth.users NOT NULL,
  drawn_at    date NOT NULL,
  marker_key  text NOT NULL,
  value       numeric NOT NULL,
  lab_source  text CHECK (lab_source IN ('manual', 'labcorp_pdf', 'quest_pdf', 'csv')),
  created_at  timestamptz DEFAULT now(),
  UNIQUE (user_id, drawn_at, marker_key)
);

CREATE INDEX IF NOT EXISTS lab_markers_user_date
  ON lab_markers (user_id, drawn_at DESC);

CREATE INDEX IF NOT EXISTS lab_markers_user_marker_date
  ON lab_markers (user_id, marker_key, drawn_at DESC);

ALTER TABLE lab_markers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own lab markers"
  ON lab_markers
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
