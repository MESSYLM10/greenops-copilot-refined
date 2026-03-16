/**
 * CarbonChart — Chart.js bar chart of gCO₂/kWh by region
 */
import { useEffect, useRef } from "react";
import Chart from "chart.js/auto";

export default function CarbonChart({ data, isLoading }) {
  const canvasRef = useRef(null);
  const chartRef = useRef(null);

  useEffect(() => {
    if (!canvasRef.current) return;
    if (chartRef.current) chartRef.current.destroy();

    chartRef.current = new Chart(canvasRef.current, {
      type: "bar",
      data: data?.chart || { labels: [], datasets: [] },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: (ctx) => ` ${ctx.raw} gCO₂/kWh`,
            },
          },
        },
        scales: {
          x: {
            grid: { color: "#ffffff0f" },
            ticks: { color: "#9ba3b2" },
          },
          y: {
            grid: { color: "#ffffff0f" },
            ticks: { color: "#9ba3b2", callback: (v) => `${v}` },
            title: { display: true, text: "gCO₂/kWh", color: "#9ba3b2" },
          },
        },
      },
    });

    return () => chartRef.current?.destroy();
  }, [data]);

  return (
    <div style={{ background: "#161b27", borderRadius: 10, padding: "16px 20px", border: "1px solid #1d2333" }}>
      <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 12 }}>
        <span style={{ fontSize: 13, fontWeight: 600, color: "#e8eaf0" }}>Live carbon intensity</span>
        <span style={{ fontSize: 11, color: "#9ba3b2" }}>
          {isLoading ? "Loading…" : "gCO₂/kWh — lower is greener"}
        </span>
      </div>
      <div style={{ height: 200 }}>
        {isLoading ? (
          <div style={{ height: "100%", display: "flex", alignItems: "center", justifyContent: "center", color: "#9ba3b2", fontSize: 13 }}>
            Fetching carbon data…
          </div>
        ) : (
          <canvas ref={canvasRef} />
        )}
      </div>
      <div style={{ display: "flex", gap: 16, marginTop: 12 }}>
        <LegendItem color="#1d9e75" label="Above 70% renewable" />
        <LegendItem color="#e65100" label="Below 70% renewable" />
      </div>
    </div>
  );
}

function LegendItem({ color, label }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
      <div style={{ width: 10, height: 10, borderRadius: 2, background: color }} />
      <span style={{ fontSize: 11, color: "#9ba3b2" }}>{label}</span>
    </div>
  );
}
