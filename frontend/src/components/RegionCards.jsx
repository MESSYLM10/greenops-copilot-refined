export default function RegionCards({ data, onRegionClick }) {
  if (!data?.regions?.length) return null;

  return (
    <div style={{ background: "#161b27", borderRadius: 10, padding: "16px 20px", border: "1px solid #1d2333" }}>
      <div style={{ fontSize: 13, fontWeight: 600, color: "#e8eaf0", marginBottom: 12 }}>Region status</div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 8 }}>
        {data.regions.map((r) => (
          <button
            key={r.region}
            onClick={() => onRegionClick?.(r.region)}
            title={`Ask about ${r.label}`}
            style={{
              background: r.region === data.greenest_now ? "#0d2e22" : "#1a1f2e",
              border: `1px solid ${r.region === data.greenest_now ? "#1d9e75" : r.renewable_flag ? "#1d9e7544" : "#e6510044"}`,
              borderRadius: 8, padding: "10px 8px", cursor: "pointer", textAlign: "left",
            }}
          >
            <div style={{ fontSize: 11, color: "#9ba3b2", marginBottom: 4 }}>
              {r.region === data.greenest_now ? "🌿 " : ""}{r.label}
            </div>
            <div style={{ fontSize: 18, fontWeight: 700, color: r.renewable_flag ? "#1d9e75" : "#e65100" }}>
              {r.current_gco2_kwh}
            </div>
            <div style={{ fontSize: 10, color: "#6b7280" }}>gCO₂/kWh</div>
            {r.renewable_pct != null && (
              <div style={{ fontSize: 10, color: "#9ba3b2", marginTop: 3 }}>
                {r.renewable_pct.toFixed(0)}% renewable
              </div>
            )}
          </button>
        ))}
      </div>
    </div>
  );
}
