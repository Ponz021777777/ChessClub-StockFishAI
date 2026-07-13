import os
import threading
from flask import Flask, request, jsonify
import chess
import chess.engine

app = Flask(__name__)

# Dynamic path targeting the local 'stockfish' Linux binary inside your repository
STOCKFISH_PATH = os.path.join(os.path.dirname(__file__), "stockfish")
engine = None
calculation_lock = threading.Lock()

def spawn_engine():
    global engine
    try:
        if engine:
            engine.quit()
    except:
        pass
    
    # Verify the binary exists and has execution permissions
    if not os.path.exists(STOCKFISH_PATH):
        print(f"[-] CRITICAL ERROR: Stockfish binary not found at {STOCKFISH_PATH}!")
        return
        
    engine = chess.engine.SimpleEngine.popen_uci(STOCKFISH_PATH)

# Initial engine bootup
spawn_engine()

@app.route('/get-best-move', methods=['POST'])
def get_best_move():
    global engine
    with calculation_lock:
        try:
            data = request.get_json()
            if not data or 'fen' not in data:
                return jsonify({"error": "Missing FEN string"}), 400
            
            fen_string = data['fen']
            depth_limit = int(data.get('depth', 6)) # Default to 6 for faster free-tier speeds
            
            print(f"[+] Processing FEN: {fen_string} (Depth: {depth_limit})")
            
            # Auto-healing mechanism if the background process dies
            if engine is None or engine.transport.is_closing():
                print("[!] Warning: Detected dead engine loop! Auto-healing...")
                spawn_engine()

            board = chess.Board(fen_string)
            result = engine.play(board, chess.engine.Limit(depth=depth_limit))
            best_move = result.move.uci()
            
            print(f"[+] Move computed safely: {best_move}")
            return jsonify({"best_move": best_move})
                
        except Exception as e:
            print(f"[-] Move computation interrupted: {str(e)}")
            print("[!] Engine error triggered. Forcing immediate reset for the next turn...")
            spawn_engine()
            return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    print("[*] Stockfish API server is starting up...")
    # Render dynamically assigns an environment port. This fallback defaults to 5000 if run locally.
    port = int(os.environ.get("PORT", 5000))
    try:
        app.run(host='0.0.0.0', port=port, debug=False, threaded=False)
    finally:
        print("[*] Terminating master background engine process...")
        if engine:
            try: engine.quit()
            except: pass
