import Anthropic from 'npm:@anthropic-ai/sdk@0.36.3';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const PROMPT = `You are a medical lab report parser. Extract every numeric lab biomarker from this report.

Return ONLY a valid JSON object — no markdown, no explanation, just JSON:
{
  "date": "YYYY-MM-DD",
  "lab": "lab/clinic name",
  "markers": [
    { "name": "standardized marker name", "value": 123.4, "unit": "unit", "ref_low": 0.0_or_null, "ref_high": 100.0_or_null, "flag": "H" | "L" | null }
  ]
}

Rules:
- Use full standard clinical names: "Total Testosterone", "Estradiol", "Hematocrit", "LDL Cholesterol", "HDL Cholesterol", "Hemoglobin", "WBC", "RBC", "Platelets", "ALT", "AST", "Creatinine", "BUN", "eGFR", "TSH", "Free T3", "Total T4", "SHBG", "IGF-1", "LH", "FSH", "DHT", "DHEA-S", "Prolactin", "PSA", "Ferritin", "Vitamin D", "hs-CRP", "Apolipoprotein B", "Total Cholesterol", "Triglycerides", "Fasting Glucose", "HbA1c", "Fasting Insulin", "ALP", "GGT", "Total Bilirubin", "Cystatin C"
- Skip qualitative or non-numeric results (e.g. "Negative", "Detected")
- Reference range ">40": ref_low=40, ref_high=null. Range "<100": ref_low=null, ref_high=100
- Date = specimen collection date (not report date)
- Include ALL numeric markers found, even uncommon ones
- flag: "H" if marked high/above range, "L" if low/below range, null if normal or not flagged`;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  try {
    const { pdf } = await req.json() as { pdf: string };
    if (!pdf) throw new Error('No PDF data provided');

    const client = new Anthropic({ apiKey: Deno.env.get('ANTHROPIC_API_KEY')! });

    const msg = await client.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 4096,
      messages: [{
        role: 'user',
        content: [
          {
            type: 'document',
            source: { type: 'base64', media_type: 'application/pdf', data: pdf },
          },
          { type: 'text', text: PROMPT },
        ],
      }],
    });

    const raw = msg.content[0].type === 'text' ? msg.content[0].text : '';
    const jsonMatch = raw.match(/\{[\s\S]*\}/);
    if (!jsonMatch) throw new Error('Claude returned no JSON');

    const result = JSON.parse(jsonMatch[0]);

    return new Response(JSON.stringify(result), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    });
  }
});
