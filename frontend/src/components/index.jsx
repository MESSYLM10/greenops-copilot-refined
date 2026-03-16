/**
 * VoiceControl — mic button, connection status, agent state indicator
 */
export function VoiceControl({ isConnected, isListening, agentState, onStart, onStop, onToggleMic }) {
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

      {/* Agent state pulse indicator */}
      <div style={{
        width: 80, height: 80, borderRadius: "50%", margin: "0 auto 16px",
        background: `${STATE_COLORS[agentState]}22`,
        border: `2px solid ${STATE_COLORS[agentState]}`,
        display: "flex", alignItems: "center", justifyContent: "center",
        transition: "all 0.3s ease",
        animation: agentState !== "idle" ? "pulse 1.5s ease-in-out infinite" : "none",
      }}>
        <span style={{ fontSize: 28 }}>
          {agentState === "speaking" ? "🔊" : agentState === "thinking" ? "⚡" : "🎤"}
        </span>
      </div>

      <div style={{ fontSize: 13, color: STATE_COLORS[agentState], marginBottom: 20, fontWeight: 500 }}>
        {STATE_LABELS[agentState]}
      </div>

      {!isConnected ? (
        <button onClick={onStart} style={btnStyle("#1d9e75")}>
          Start session
        </button>
      ) : (
        <div style={{ display: "flex", gap: 10, justifyContent: "center" }}>
          <button onClick={onToggleMic} style={btnStyle(isListening ? "#e65100" : "#1d9e75")}>
            {isListening ? "Mute mic" : "Unmute mic"}
          </button>
          <button onClick={onStop} style={btnStyle("#374151")}>
            End
          </button>
        </div>
      )}

      <div style={{ marginTop: 14, fontSize: 11, color: "#4b5563" }}>
        {isConnected ? "Share your screen to enable vision" : "Click to connect to Gemini Live"}
      </div>

      <style>{`
        @keyframes pulse {
          0%, 100% { transform: scale(1); opacity: 1; }
          50% { transform: scale(1.05); opacity: 0.85; }
        }
      `}</style>
    </div>
  );
}

function btnStyle(bg) {
  return {
    background: bg, color: "#fff", border: "none", borderRadius: 8,
    padding: "10px 20px", fontSize: 13, fontWeight: 600, cursor: "pointer",
    transition: "opacity 0.15s",
  };
}

/**
 * RegionCards — compact grid of region status cards
 */
export function RegionCards({ data, onRegionClick }) {
  if (!data?.regions?.length) return null;

  return (
    <div style={{ background: "#161b27", borderRadius: 10, padding: "16px 20px", border: "1px solid #1d2333" }}>
      <div style={{ fontSize: 13, fontWeight: 600, color: "#e8eaf0", marginBottom: 12 }}>
        Region status
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 8 }}>
        {data.regions.map((r) => (
          <RegionCard
            key={r.region}
            region={r}
            isGreenest={r.region === data.greenest_now}
            onClick={() => onRegionClick?.(r.region)}
          />
        ))}
      </div>
    </div>
  );
}

function RegionCard({ region, isGreenest, onClick }) {
  const isGreen = region.renewable_flag;
  return (
    <button
      onClick={onClick}
      style={{
        background: isGreenest ? "#0d2e22" : "#1a1f2e",
        border: `1px solid ${isGreenest ? "#1d9e75" : isGreen ? "#1d9e7544" : "#e6510044"}`,
        borderRadius: 8, padding: "10px 8px", cursor: "pointer", textAlign: "left",
        transition: "border-color 0.2s",
      }}
    >
      <div style={{ fontSize: 11, color: "#9ba3b2", marginBottom: 4 }}>
        {isGreenest ? "🌿 " : ""}{region.label}
      </div>
      <div style={{ fontSize: 18, fontWeight: 700, color: isGreen ? "#1d9e75" : "#e65100" }}>
        {region.current_gco2_kwh}
      </div>
      <div style={{ fontSize: 10, color: "#6b7280" }}>gCO₂/kWh</div>
      {region.renewable_pct != null && (
        <div style={{ fontSize: 10, color: "#9ba3b2", marginTop: 4 }}>
          {region.renewable_pct.toFixed(0)}% renewable
        </div>
      )}
    </button>
  );
}

/**
 * JobQueue — list of scheduled workloads
 */
export function JobQueue({ jobs }) {
  if (!jobs?.length) return (
    <div style={{ background: "#161b27", borderRadius: 10, padding: "16px 20px", border: "1px solid #1d2333" }}>
      <div style={{ fontSize: 13, fontWeight: 600, color: "#e8eaf0", marginBottom: 8 }}>Scheduled jobs</div>
      <div style={{ fontSize: 12, color: "#4b5563" }}>No jobs scheduled yet. Ask the agent to schedule a workload.</div>
    </div>
  );

  return (
    <div style={{ background: "#161b27", borderRadius: 10, padding: "16px 20px", border: "1px solid #1d2333" }}>
      <div style={{ fontSize: 13, fontWeight: 600, color: "#e8eaf0", marginBottom: 12 }}>Scheduled jobs</div>
      <div style={{ display: "flex", flexDirection: "column", gap: 8, maxHeight: 280, overflowY: "auto" }}>
        {jobs.map((job) => (
          <div key={job.job_id} style={{
            background: "#1a1f2e", borderRadius: 8, padding: "10px 12px",
            border: "1px solid #1d9e7533",
          }}>
            <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
              <span style={{ fontSize: 11, color: "#1d9e75", fontWeight: 600 }}>{job.region_display}</span>
              <span style={{ fontSize: 10, color: "#9ba3b2" }}>
                {new Date(job.scheduled_for).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
              </span>
            </div>
            <div style={{ fontSize: 11, color: "#e8eaf0", marginBottom: 4 }}>{job.workload_description?.slice(0, 60)}</div>
            <div style={{ fontSize: 10, color: "#6b7280" }}>
              Saves ~{job.co2_saved_kg} kg CO₂ · {job.co2_reduction_pct}% reduction
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

/**
 * SavingsCounter — cumulative CO₂ savings display
 */
export function SavingsCounter({ orchestratorUrl }) {
  const [savings, setSavings] = useState(null);

  useEffect(() => {
    fetch(`${orchestratorUrl}/api/carbon/history?days=30`)
      .then((r) => r.json())
      .then((d) => setSavings(d))
      .catch(() => {});
  }, [orchestratorUrl]);

  return (
    <div style={{
      background: "linear-gradient(135deg, #0d2e22, #1a1f2e)",
      borderRadius: 10, padding: "16px 20px",
      border: "1px solid #1d9e75",
      display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 16,
    }}>
      <Stat
        value={savings ? `${savings.total_co2_saved_kg} kg` : "—"}
        label="CO₂ saved (30d)"
        color="#1d9e75"
      />
      <Stat
        value={savings ? savings.jobs_scheduled : "—"}
        label="Jobs scheduled"
        color="#6366f1"
      />
      <Stat
        value={savings ? `${savings.avg_reduction_pct}%` : "—"}
        label="Avg reduction"
        color="#f59e0b"
      />
    </div>
  );
}

function Stat({ value, label, color }) {
  return (
    <div style={{ textAlign: "center" }}>
      <div style={{ fontSize: 22, fontWeight: 700, color }}>{value}</div>
      <div style={{ fontSize: 11, color: "#9ba3b2", marginTop: 4 }}>{label}</div>
    </div>
  );
}

/**
 * StatusBar — connection status and last-updated time
 */
export function StatusBar({ isConnected, agentState, lastUpdated, onRefresh }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
        <div style={{
          width: 8, height: 8, borderRadius: "50%",
          background: isConnected ? "#1d9e75" : "#6b7280",
        }} />
        <span style={{ fontSize: 12, color: "#9ba3b2" }}>
          {isConnected ? "Live" : "Offline"}
        </span>
      </div>
      {lastUpdated && (
        <span style={{ fontSize: 11, color: "#4b5563" }}>
          Updated {lastUpdated.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
        </span>
      )}
      <button
        onClick={onRefresh}
        style={{ background: "none", border: "1px solid #1d2333", borderRadius: 6, padding: "4px 10px", fontSize: 11, color: "#9ba3b2", cursor: "pointer" }}
      >
        Refresh
      </button>
    </div>
  );
}

// needed for SavingsCounter
import { useState } from "react";
