import { useState, useEffect } from "react";

export default function SavingsCounter({ orchestratorUrl }) {
  const [data, setData] = useState(null);
  const [prev, setPrev] = useState(null);

  useEffect(() => {
    const load = () =>
      fetch(`${orchestratorUrl}/api/carbon/history?days=30`)
        .then((r) => r.json())
        .then((d) => {
          setPrev((p) => p ?? d);
          setData(d);
        })
        .catch(() => {});
    load();
    const t = setInterval(load, 120_000);
    return () => clearInterval(t);
  }, [orchestratorUrl]);

  const delta = data && prev
    ? (data.total_co2_saved_kg - prev.total_co2_saved_kg).toFixed(1)
    : null;

  return (
    <div style={{
      background: "#0d1f19",
      borderRadius: 10, padding: "16px 20px",
      border: "1px solid #1d9e75",
      display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 16,
    }}>
      <Stat
        value={data ? `${data.total_co2_saved_kg} kg` : "—"}
        label="CO₂ saved (30d)"
        color="#1d9e75"
        delta={delta > 0 ? `+${delta} kg` : null}
      />
      <Stat
        value={data ? data.jobs_scheduled : "—"}
        label="Jobs scheduled"
        color="#6366f1"
      />
      <Stat
        value={data ? `${data.avg_reduction_pct}%` : "—"}
        label="Avg reduction"
        color="#f59e0b"
      />
    </div>
  );
}

function Stat({ value, label, color, delta }) {
  return (
    <div style={{ textAlign: "center" }}>
      <div style={{ fontSize: 22, fontWeight: 700, color, lineHeight: 1 }}>{value}</div>
      {delta && (
        <div style={{ fontSize: 10, color: "#1d9e75", marginTop: 2 }}>{delta} today</div>
      )}
      <div style={{ fontSize: 11, color: "#9ba3b2", marginTop: 4 }}>{label}</div>
    </div>
  );
}
