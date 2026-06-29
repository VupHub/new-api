package common

import (
	"fmt"
	"net/url"
	"strings"
	"time"

	"github.com/getsentry/sentry-go"
)

type SentryMode string

const (
	SentryModeDisabled   SentryMode = "disabled"
	SentryModeOfficial   SentryMode = "official"
	SentryModeSelfHosted SentryMode = "self-hosted"
)

func ParseSentryMode(raw string) (SentryMode, error) {
	mode := SentryMode(strings.ToLower(strings.TrimSpace(raw)))
	switch mode {
	case "", SentryModeDisabled:
		return SentryModeDisabled, nil
	case SentryModeOfficial, "saas":
		return SentryModeOfficial, nil
	case SentryModeSelfHosted, "selfhosted", "self_hosted":
		return SentryModeSelfHosted, nil
	default:
		return "", fmt.Errorf("unsupported SENTRY_MODE %q, expected official, self-hosted, or disabled", raw)
	}
}

func isOfficialSentryDSN(dsn string) bool {
	parsed, err := url.Parse(strings.TrimSpace(dsn))
	if err != nil {
		return false
	}
	host := strings.ToLower(parsed.Hostname())
	return host == "sentry.io" || strings.HasSuffix(host, ".sentry.io")
}

func InitSentry(version string) bool {
	dsn := strings.TrimSpace(GetEnvOrDefaultString("SENTRY_DSN", ""))

	modeRaw := GetEnvOrDefaultString("SENTRY_MODE", "")
	var (
		mode SentryMode
		err  error
	)
	if modeRaw == "" {
		if dsn == "" {
			SysLog("Sentry is disabled")
			return false
		}
		if isOfficialSentryDSN(dsn) {
			mode = SentryModeOfficial
		} else {
			mode = SentryModeSelfHosted
		}
	} else {
		mode, err = ParseSentryMode(modeRaw)
		if err != nil {
			SysError(err.Error())
			return false
		}
	}

	if mode == SentryModeDisabled {
		SysLog("Sentry is disabled")
		return false
	}
	if dsn == "" {
		SysError(fmt.Sprintf("Sentry mode %q requires SENTRY_DSN, disabling Sentry", mode))
		return false
	}
	if mode == SentryModeOfficial && !isOfficialSentryDSN(dsn) {
		SysError("Sentry official mode requires a sentry.io DSN, disabling Sentry")
		return false
	}

	environment := GetEnvOrDefaultString("SENTRY_ENVIRONMENT", "")
	if environment == "" {
		if DebugEnabled {
			environment = "development"
		} else {
			environment = "production"
		}
	}

	release := GetEnvOrDefaultString("SENTRY_RELEASE", "new-api@"+version)
	enableTracing := GetEnvOrDefaultBool("SENTRY_ENABLE_TRACING", true)
	tracesSampleRate := GetEnvOrDefaultFloat64("SENTRY_TRACES_SAMPLE_RATE", 0.1)
	debug := GetEnvOrDefaultBool("SENTRY_DEBUG", DebugEnabled)
	sendDefaultPII := GetEnvOrDefaultBool("SENTRY_SEND_DEFAULT_PII", false)

	err = sentry.Init(sentry.ClientOptions{
		Dsn:              dsn,
		Release:          release,
		Environment:      environment,
		EnableTracing:    enableTracing,
		TracesSampleRate: tracesSampleRate,
		SendDefaultPII:   sendDefaultPII,
		Debug:            debug,
	})
	if err != nil {
		SysError(fmt.Sprintf("Sentry initialization failed: %v", err))
		return false
	}

	SysLog(fmt.Sprintf("Sentry initialized successfully (mode=%s, environment=%s)", mode, environment))
	return true
}

func FlushSentry(timeout time.Duration) {
	sentry.Flush(timeout)
}
