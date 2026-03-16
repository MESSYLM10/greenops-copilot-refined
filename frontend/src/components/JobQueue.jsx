export default function JobQueue({ jobs }) {
  if (!jobs?.length) return (
    <div style={{ background: "#161b27", borderRadius: 10, padding: "16px 20px", border: "1px solid #1d2333" }}>
      <div style={{ fontSize: 13, fontWeight: 600, color: "#e8eaf0", marginBottom: 8 }}>Scheduled jobs</div>
      <div style={{ fontSize: 12, color: "#4b5563" }}>
        No jobs scheduled yet. Ask the agent to schedule a workload.
      </div>
    </div>
  );

  return (
    <div style={{ background: "#161b27", borderRadius: 10, padding: "16px 20px", border: "1px solid #1d2333" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }}>
        <span style={{ fontSize: 13, fontWeight: 600, color: "#e8eaf0" }}>Scheduled jobs</span>
        <span style={{
          fontSize: 11, fontWeight: 600, background: "#1d9e7522",
          color: "#1d9e75", borderRadius: 20, padding: "2px 10px",
        }}>{jobs.length}</span>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 8, maxHeight: 300, overflowY: "auto" }}>
        {jobs.map((job) => (
          <div key={job.job_id} style={{
            background: "#1a1f2e", borderRadius: 8, padding: "10px 12px",
            border: "1px solid #1d9e7533",
          }}>
            <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
              <span style={{ fontSize: 11, color: "#1d9e75", fontWeight: 600 }}>{job.region_display}</span>
              <span style={{ fontSize: 10, color: "#9ba3b2" }}>
                {new Date(job.scheduled_for).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })} UTC
              </span>
            </div>
            <div style={{ fontSize: 11, color: "#e8eaf0", marginBottom: 4 }}>
              {job.workload_description?.slice(0, 60)}{job.workload_description?.length > 60 ? "…" : ""}
            </div>
            <div style={{ fontSize: 10, color: "#6b7280" }}>
              Saves ~{job.co2_saved_kg} kg CO₂ · {job.co2_reduction_pct}% reduction
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
