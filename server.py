import http.server, socketserver, os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
PORT = 3000
handler = http.server.SimpleHTTPRequestHandler
with socketserver.TCPServer(("", PORT), handler) as httpd:
    print(f"🚀 Local server running at http://localhost:3000")
    print("Press Ctrl+C to stop")
    httpd.serve_forever()
