export default function VoiceControl({ isConnected, isListening, agentState, onStart, onStop, onToggleMic }) {
  const STATE_LABELS = {
    idle: "Ready",
    listening: "Listening…",
    thinking: "Thinking…",
    speaking: "Speaking…",
  };
  const STATE_COLORS = {
    idle: "#9ba3b2",
    listening: "#1d9e75",
    thinking: "#f59e0b",
    speaking: "#6366f1",
  };
  const STATE_ICONS = { idle: "🎤", listening: "🎤", thinking: "⚡", speaking: "🔊" };

  return (
    <div style={{
      background: "#161b27", borderRadius: 10, padding: "20px",
      border: "1px solid #1d2333", textAlign: "center",
    }}>
      <div style={{ marginBottom: 16 }}>
        <span style={{ fontSize: 12, fontWeight: 600, color: "#9ba3b2", textTransform: "uppercase", letterSpacing: "0.08em" }}>
          GreenOps Copilot
        </span>
      </div>

      <div style={{
        width: 80, height: 80, borderRadius: "50%", margin: "0 auto 16px",
        background: `${STATE_COLORS[agentState]}22`,
        border: `2px solid ${STATE_COLORS[agentState]}`,
        display: "flex", alignItems: "center", justifyContent: "center",
        transition: "all 0.3s ease",
        animation: agentState !== "idle" ? "pulse 1.5s ease-in-out infinite" : "none",
      }}>
        <span style={{ fontSize: 28 }}>{STATE_ICONS[agentState]}</span>
      </div>

      <div style={{ fontSize: 13, color: STATE_COLORS[agentState], marginBottom: 20, fontWeight: 500 }}>
        {STATE_LABELS[agentState]}
      </div>

      {!isConnected ? (
        <button onClick={onStart} style={btn("#1d9e75")}>Start session</button>
      ) : (
        <div style={{ display: "flex", gap: 10, justifyContent: "center" }}>
          <button onClick={onToggleMic} style={btn(isListening ? "#e65100" : "#1d9e75")}>
            {isListening ? "Mute mic" : "Unmute mic"}
          </button>
          <button onClick={onStop} style={btn("#374151")}>End</button>
        </div>
      )}

      <div style={{ marginTop: 14, fontSize: 11, color: "#4b5563" }}>
        {isConnected ? "Share your screen to enable vision" : "Click to connect to Gemini Live"}
      </div>

      <style>{`
        @keyframes pulse {
          0%,100%{transform:scale(1);opacity:1}
          50%{transform:scale(1.06);opacity:0.85}
        }
      `}</style>
    </div>
  );
}

const btn = (bg) => ({
  background: bg, color: "#fff", border: "none", borderRadius: 8,
  padding: "10px 20px", fontSize: 13, fontWeight: 600, cursor: "pointer",
});
