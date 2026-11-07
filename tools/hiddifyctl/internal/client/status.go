package client

import (
	"fmt"
	"strings"
)

// Status is a structured view of the core connection, suitable for both CLI
// printing and JSON serialization for MCP tools.
type Status struct {
	State            string `json:"state"`
	CurrentProfile   string `json:"current_profile"`
	CurrentOutbound  string `json:"current_outbound"`
	Uplink           int64  `json:"uplink"`
	Downlink         int64  `json:"downlink"`
	UplinkTotal      int64  `json:"uplink_total"`
	DownlinkTotal    int64  `json:"downlink_total"`
	TrafficAvailable bool   `json:"traffic_available"`
}

// IsConnected reports whether the core is (or is becoming) connected.
func (s *Status) IsConnected() bool {
	return s.State == "STARTED" || s.State == "STARTING" || s.State == "HOT_RELOADING"
}

func orNA(s string) string {
	if s == "" {
		return "n/a"
	}
	return s
}

func humanBytes(n int64) string {
	if n <= 0 {
		return "0 B"
	}
	units := []string{"B", "KB", "MB", "GB", "TB", "PB"}
	f := float64(n)
	i := 0
	for f >= 1024 && i < len(units)-1 {
		f /= 1024
		i++
	}
	if i == 0 {
		return fmt.Sprintf("%d %s", int64(f), units[i])
	}
	return fmt.Sprintf("%.2f %s", f, units[i])
}

// String renders a human-friendly, multi-line status report.
func (s *Status) String() string {
	var b strings.Builder
	fmt.Fprintf(&b, "State:            %s\n", s.State)
	fmt.Fprintf(&b, "Current profile:  %s\n", orNA(s.CurrentProfile))
	fmt.Fprintf(&b, "Current node:     %s\n", orNA(s.CurrentOutbound))
	if s.TrafficAvailable {
		fmt.Fprintf(&b, "Traffic (up/down): %s / %s\n", humanBytes(s.Uplink), humanBytes(s.Downlink))
		fmt.Fprintf(&b, "Total  (up/down): %s / %s\n", humanBytes(s.UplinkTotal), humanBytes(s.DownlinkTotal))
	}
	return b.String()
}
