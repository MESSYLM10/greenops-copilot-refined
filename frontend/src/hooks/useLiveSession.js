/**
 * useLiveSession
 * Manages the WebSocket connection to the ADK Orchestrator,
 * captures mic audio (PCM 16kHz), throttles screen-share frames (1fps),
 * plays back synthesised speech from the agent.
 */

import { useState, useRef, useCallback, useEffect } from "react";

const AUDIO_SAMPLE_RATE = 16000;
const VISION_FPS = 1;

export function useLiveSession({
  orchestratorUrl,
  sessionId: initialSessionId,
  onSessionId,
  onJobScheduled,
}) {
  const [isConnected, setIsConnected] = useState(false);
  const [isListening, setIsListening] = useState(false);
  const [agentState, setAgentState] = useState("idle"); // idle | listening | thinking | speaking

  const wsRef = useRef(null);
  const audioCtxRef = useRef(null);
  const mediaStreamRef = useRef(null);
  const processorRef = useRef(null);
  const screenStreamRef = useRef(null);
  const visionIntervalRef = useRef(null);
  const canvasRef = useRef(document.createElement("canvas"));
  const sessionIdRef = useRef(initialSessionId);
  const outputQueueRef = useRef([]);
  const isPlayingRef = useRef(false);

  // ── WebSocket ───────────────────────────────────────────────────────────────

  const connect = useCallback(() => {
    const wsUrl = orchestratorUrl
      .replace(/^http/, "ws")
      .replace(/\/$/, "");
    const params = sessionIdRef.current ? `?session_id=${sessionIdRef.current}` : "";
    const ws = new WebSocket(`${wsUrl}/live${params}`);
    wsRef.current = ws;

    ws.onopen = () => {
      setIsConnected(true);
      setAgentState("idle");
    };

    ws.onmessage = (event) => {
      const msg = JSON.parse(event.data);

      if (msg.type === "status") {
        if (msg.session_id && msg.session_id !== "new") {
          sessionIdRef.current = msg.session_id;
          onSessionId?.(msg.session_id);
        }
      }

      if (msg.type === "audio") {
        // Queue audio for sequential playback
        outputQueueRef.current.push(msg.data);
        setAgentState("speaking");
        if (!isPlayingRef.current) {
          playNextAudio();
        }
      }

      if (msg.type === "tool_call_start") {
        setAgentState("thinking");
      }

      if (msg.type === "job_scheduled" && msg.job) {
        onJobScheduled?.(msg.job);
      }

      if (msg.type === "error") {
        console.error("Agent error:", msg.message);
        setAgentState("idle");
      }
    };

    ws.onclose = () => {
      setIsConnected(false);
      setIsListening(false);
      setAgentState("idle");
    };

    ws.onerror = (e) => {
      console.error("WebSocket error:", e);
    };
  }, [orchestratorUrl, onSessionId, onJobScheduled]);

  // ── Audio playback ──────────────────────────────────────────────────────────

  const playNextAudio = useCallback(async () => {
    if (outputQueueRef.current.length === 0) {
      isPlayingRef.current = false;
      setAgentState("idle");
      return;
    }

    isPlayingRef.current = true;
    const b64 = outputQueueRef.current.shift();

    try {
      const ctx = audioCtxRef.current || new AudioContext({ sampleRate: 24000 });
      audioCtxRef.current = ctx;

      const binary = atob(b64);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);

      const audioBuffer = await ctx.decodeAudioData(bytes.buffer);
      const source = ctx.createBufferSource();
      source.buffer = audioBuffer;
      source.connect(ctx.destination);
      source.onended = playNextAudio;
      source.start();
    } catch (e) {
      console.warn("Audio playback error:", e);
      playNextAudio();
    }
  }, []);

  // ── Mic capture ─────────────────────────────────────────────────────────────

  const startMic = useCallback(async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      mediaStreamRef.current = stream;

      const ctx = new AudioContext({ sampleRate: AUDIO_SAMPLE_RATE });
      audioCtxRef.current = ctx;
      const source = ctx.createMediaStreamSource(stream);

      const processor = ctx.createScriptProcessor(4096, 1, 1);
      processorRef.current = processor;

      processor.onaudioprocess = (e) => {
        if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) return;
        const float32 = e.inputBuffer.getChannelData(0);
        const int16 = float32ToInt16(float32);
        const b64 = btoa(String.fromCharCode(...new Uint8Array(int16.buffer)));
        wsRef.current.send(JSON.stringify({ type: "audio", data: b64 }));
      };

      source.connect(processor);
      processor.connect(ctx.destination);
      setIsListening(true);
      setAgentState("listening");
    } catch (e) {
      console.error("Mic access denied:", e);
    }
  }, []);

  const stopMic = useCallback(() => {
    processorRef.current?.disconnect();
    mediaStreamRef.current?.getTracks().forEach((t) => t.stop());
    setIsListening(false);
    if (agentState === "listening") setAgentState("idle");
  }, [agentState]);

  // ── Screen capture (vision stream) ─────────────────────────────────────────

  const startScreenShare = useCallback(async () => {
    try {
      const stream = await navigator.mediaDevices.getDisplayMedia({ video: true });
      screenStreamRef.current = stream;

      const video = document.createElement("video");
      video.srcObject = stream;
      video.play();

      const canvas = canvasRef.current;
      canvas.width = 640;
      canvas.height = 360;
      const ctx2d = canvas.getContext("2d");

      visionIntervalRef.current = setInterval(() => {
        if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) return;
        ctx2d.drawImage(video, 0, 0, 640, 360);
        const frameData = canvas.toDataURL("image/jpeg", 0.6).split(",")[1];
        wsRef.current.send(JSON.stringify({ type: "vision", data: frameData }));
      }, 1000 / VISION_FPS);

      stream.getVideoTracks()[0].onended = stopScreenShare;
    } catch (e) {
      console.warn("Screen share not started:", e);
    }
  }, []);

  const stopScreenShare = useCallback(() => {
    clearInterval(visionIntervalRef.current);
    screenStreamRef.current?.getTracks().forEach((t) => t.stop());
    screenStreamRef.current = null;
  }, []);

  // ── Public API ──────────────────────────────────────────────────────────────

  const startSession = useCallback(async () => {
    connect();
    await startMic();
    await startScreenShare();
  }, [connect, startMic, startScreenShare]);

  const stopSession = useCallback(() => {
    stopMic();
    stopScreenShare();
    wsRef.current?.send(JSON.stringify({ type: "close" }));
    wsRef.current?.close();
    setIsConnected(false);
  }, [stopMic, stopScreenShare]);

  const toggleMic = useCallback(() => {
    isListening ? stopMic() : startMic();
  }, [isListening, startMic, stopMic]);

  useEffect(() => {
    return () => {
      stopSession();
    };
  }, []);

  return { isConnected, isListening, agentState, startSession, stopSession, toggleMic };
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function float32ToInt16(float32Array) {
  const int16 = new Int16Array(float32Array.length);
  for (let i = 0; i < float32Array.length; i++) {
    const s = Math.max(-1, Math.min(1, float32Array[i]));
    int16[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
  }
  return int16;
}
