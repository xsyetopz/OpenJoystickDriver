/// Whether `seconds` is a usable `--timeout`, `OJD_TIMEOUT`, or `--duration` value.
func isPositiveSeconds(_ seconds: Double) -> Bool { seconds.isFinite && seconds > 0 }
