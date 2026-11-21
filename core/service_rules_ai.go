package core

import (
	"slices"

	"github.com/metacubex/http"
)

var (
	copilotBlockedRegions    = []string{"CN", "RU", "BY", "KP", "IR", "SY", "CU"}
	grokBlockedRegions       = []string{"CN", "HK", "MO", "RU", "BY", "KP", "IR", "SY", "CU"}
	perplexityBlockedRegions = []string{"CN", "KP", "IR", "SY", "CU", "RU"}
)

// checkPerplexity probes Cloudflare trace + landing response for Perplexity AI.
func checkPerplexity(env serviceEnv) ServiceCheckItem {
	trace := env.get("https://www.perplexity.ai/cdn-cgi/trace", serviceSmallMaxBody)
	item := itemFrom(trace)
	if answered(item, trace) {
		item.Region = normalizeRegion(traceValue(trace.Body, "loc"))
	}

	home := env.get("https://www.perplexity.ai/", serviceSmallMaxBody)
	homeItem := itemFrom(home)
	if !answered(homeItem, home) {
		if item.Region != "" && slices.Contains(perplexityBlockedRegions, item.Region) {
			item.Status = serviceUnsupportedRegion
			return item
		}
		return homeItem
	}
	if item.Delay == 0 {
		item.Delay = homeItem.Delay
	}
	if len(item.Chains) == 0 {
		item.Chains = homeItem.Chains
	}
	item.Status = perplexityStatus(home, item.Region)
	return item
}

func perplexityStatus(result *ProbeResult, region string) string {
	if region != "" && slices.Contains(perplexityBlockedRegions, region) {
		return serviceUnsupportedRegion
	}
	switch {
	case result.StatusCode == http.StatusUnavailableForLegalReasons:
		return serviceUnsupportedRegion
	case result.StatusCode == http.StatusForbidden:
		if bodyContains(result, "cf-mitigated", "just a moment", "attention required", "access denied", "blocked") {
			return serviceBlocked
		}
		return serviceRestricted
	case result.StatusCode == http.StatusTooManyRequests:
		return serviceRestricted
	case result.StatusCode >= 200 && result.StatusCode < 400:
		if bodyContains(result, "not available in your country", "not available in your region") {
			return serviceUnsupportedRegion
		}
		return serviceAvailable
	default:
		return statusFromCode(result.StatusCode)
	}
}

// checkCopilot probes Microsoft Copilot availability and region redirect.
func checkCopilot(env serviceEnv) ServiceCheckItem {
	result := env.get("https://copilot.microsoft.com/", serviceSmallMaxBody)
	item := itemFrom(result)
	if !answered(item, result) {
		return item
	}
	trace := env.get("https://www.cloudflare.com/cdn-cgi/trace", serviceSmallMaxBody)
	if traceItem := itemFrom(trace); answered(traceItem, trace) {
		item.Region = normalizeRegion(traceValue(trace.Body, "loc"))
	}
	item.Status = copilotStatus(result, item.Region)
	return item
}

func copilotStatus(result *ProbeResult, region string) string {
	if region != "" && slices.Contains(copilotBlockedRegions, region) {
		return serviceUnsupportedRegion
	}
	switch {
	case bodyContains(result, "cn.bing.com", "copilot is not available in your region", "not available in your country"):
		return serviceUnsupportedRegion
	case result.StatusCode == http.StatusForbidden || result.StatusCode == http.StatusUnavailableForLegalReasons:
		return serviceBlocked
	case result.StatusCode >= 200 && result.StatusCode < 400:
		return serviceAvailable
	default:
		return statusFromCode(result.StatusCode)
	}
}

// checkGrok probes xAI Grok web & API gateway reachability and region eligibility.
func checkGrok(env serviceEnv) ServiceCheckItem {
	trace := env.get("https://grok.com/cdn-cgi/trace", serviceSmallMaxBody)
	item := itemFrom(trace)
	if answered(item, trace) {
		item.Region = normalizeRegion(traceValue(trace.Body, "loc"))
	}

	api := env.get("https://api.x.ai/v1/models", serviceSmallMaxBody)
	apiItem := itemFrom(api)
	if !answered(apiItem, api) {
		if item.Region != "" && slices.Contains(grokBlockedRegions, item.Region) {
			item.Status = serviceUnsupportedRegion
			return item
		}
		return apiItem
	}
	if item.Delay == 0 {
		item.Delay = apiItem.Delay
	}
	if len(item.Chains) == 0 {
		item.Chains = apiItem.Chains
	}
	item.Status = grokStatus(api, item.Region)
	return item
}

func grokStatus(result *ProbeResult, region string) string {
	if region != "" && slices.Contains(grokBlockedRegions, region) {
		return serviceUnsupportedRegion
	}
	switch {
	case bodyContains(result, "not available in your region", "unsupported region", "country not supported"):
		return serviceUnsupportedRegion
	case result.StatusCode == http.StatusUnauthorized || result.StatusCode == http.StatusBadRequest:
		// Reaching the xAI auth gate proves the IP and region were not geo-blocked.
		return serviceAvailable
	case result.StatusCode == http.StatusForbidden:
		if bodyContains(result, "just a moment", "attention required", "access denied") {
			return serviceBlocked
		}
		return serviceUnsupportedRegion
	case result.StatusCode >= 200 && result.StatusCode < 300:
		return serviceAvailable
	default:
		return statusFromCode(result.StatusCode)
	}
}
