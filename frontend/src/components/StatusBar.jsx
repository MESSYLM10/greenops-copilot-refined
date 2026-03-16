export default function StatusBar({ isConnected, agentState, lastUpdated, onRefresh }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
        <div style={{
          width: 8, height: 8, borderRadius: "50%",
          background: isConnected ? "#1d9e75" : "#4b5563",
          boxShadow: isConnected ? "0 0 6px #1d9e75aa" : "none",
        }} />
        <span style={{ fontSize: 12, color: "#9ba3b2" }}>
          {isConnected ? "Live" : "Offline"}
        </span>
      </div>

      {lastUpdated && (
        <span style={{ fontSize: 11, color: "#4b5563" }}>
          Carbon data: {lastUpdated.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
        </span>
      )}

      <button
        onClick={onRefresh}
        style={{
          background: "none", border: "1px solid #1d2333", borderRadius: 6,
          padding: "4px 10px", fontSize: 11, color: "#9ba3b2", cursor: "pointer",
        }}
      >
        ↻ Refresh
      </button>
    </div>
  );
}
