package core

import (
	"net/http"
	"testing"
)

func TestPerplexityStatus(t *testing.T) {
	tests := []struct {
		name   string
		result *ProbeResult
		region string
		want   string
	}{
		{
			name:   "available us",
			result: &ProbeResult{StatusCode: http.StatusOK, Body: "<html>Perplexity</html>"},
			region: "US",
			want:   serviceAvailable,
		},
		{
			name:   "unsupported region",
			result: &ProbeResult{StatusCode: http.StatusOK},
			region: "CN",
			want:   serviceUnsupportedRegion,
		},
		{
			name:   "cloudflare challenge blocked",
			result: &ProbeResult{StatusCode: http.StatusForbidden, Body: "Just a moment..."},
			region: "US",
			want:   serviceBlocked,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := perplexityStatus(tc.result, tc.region); got != tc.want {
				t.Fatalf("perplexityStatus() = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestCopilotStatus(t *testing.T) {
	if got := copilotStatus(&ProbeResult{StatusCode: http.StatusOK}, "JP"); got != serviceAvailable {
		t.Fatalf("got %q, want %q", got, serviceAvailable)
	}
	if got := copilotStatus(&ProbeResult{StatusCode: http.StatusOK, Body: "https://cn.bing.com"}, "US"); got != serviceUnsupportedRegion {
		t.Fatalf("got %q, want %q", got, serviceUnsupportedRegion)
	}
	if got := copilotStatus(&ProbeResult{StatusCode: http.StatusOK}, "CN"); got != serviceUnsupportedRegion {
		t.Fatalf("got %q, want %q", got, serviceUnsupportedRegion)
	}
}

func TestGrokStatus(t *testing.T) {
	if got := grokStatus(&ProbeResult{StatusCode: http.StatusUnauthorized}, "US"); got != serviceAvailable {
		t.Fatalf("got %q, want %q", got, serviceAvailable)
	}
	if got := grokStatus(&ProbeResult{StatusCode: http.StatusUnauthorized}, "HK"); got != serviceUnsupportedRegion {
		t.Fatalf("got %q, want %q", got, serviceUnsupportedRegion)
	}
	if got := grokStatus(&ProbeResult{StatusCode: http.StatusForbidden, Body: "Attention Required"}, "US"); got != serviceBlocked {
		t.Fatalf("got %q, want %q", got, serviceBlocked)
	}
}
