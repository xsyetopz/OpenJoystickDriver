# Measuring Input Performance

The input path costs CPU on every controller frame, so a change to it is judged by CPU time per frame, not by CPU percent alone. A faster controller raises the frame rate and the CPU percent together while the cost per frame stays the same.

## Measure a Build

1. Install the build: `just install-release`.
2. Quit the apps that read the controller, such as Steam, and close the OJD window. The window draws live input and adds its own cost.
3. Connect the controller and start moving a stick. Each round waits until the controller reads 20 frames in one second.
4. Record the run set:

   ```sh
   just perf-measure d18259e --controller 2C --note "window closed"
   ```

| Option | Default | Meaning |
| :-- | :-- | :-- |
| `--runs` | 10 | Rounds to record |
| `--seconds` | 15 | Seconds per round, at most 15 (`ojd diagnose --frames` limit) |
| `--controller` | every controller | Part of the controller name whose frames count |
| `--note` | empty | Conditions of the run, such as window state |
| `--process` | `OpenJoystickDriver` | Process whose CPU time counts |

Each round appends one JSON line to `.build/perf/<label>.jsonl`. The line holds the frame count, wall time, user and system CPU time, idle wakeups from `proc_pid_rusage`, and the app version, commit, macOS version, chip, and controller.

A round counts only when the sticks move for all of it. While input rests, the app still uses CPU, and that cost spread over fewer frames would inflate the cost per frame. The tool discards and repeats a round when:

- the controller read fewer than 20 frames a second on average
- its frames span less than the round minus 1 s
- two frames are more than 0.5 s apart

Keep the input the same across the run sets you compare: same controller, connection, stick motion, and window state.

## Compare Two Run Sets

```sh
just perf-report d18259e sender-rewrite --output .build/perf/report.md
```

The report fills [`Scripts/Diagnostics/perf_report_template.md`](../../Scripts/Diagnostics/perf_report_template.md) and pastes into a GitHub issue or pull request as it is.

| Part | Content |
| :-- | :-- |
| Environment table | Version, commit, macOS, chip, controller, and note of each run set |
| Metric table | CPU, user, and system µs per frame, idle wakeups per frame, CPU percent, frames per second |
| Cell | Median ± the 95% confidence interval of the median, as a percent |
| Δ and Δ % | Candidate median minus base median; CPU percent deltas are in percentage points (`pp`) |
| Test | Mann-Whitney U p-value and the run counts, such as `p=0.000 n=10+10` |
| Verdict | 🟢 better or 🔴 worse when p < 0.05, `~` otherwise |
| Chart | QuickChart bar chart of the median CPU, user, and system µs per frame |
| Raw runs | Every round, under a Raw Runs heading |

## Reading the Numbers

- Ten runs a side is the working minimum. With fewer than 6 runs the confidence interval is blank, and with 3 runs a side no difference reaches p < 0.05.
- The p-value is exact when no two values tie and uses the normal approximation with a tie correction otherwise.
- System time counts kernel work the app asks for, such as USB reads and virtual HID reports. It is often half the total, so a change that removes a system call shows there.
- Idle wakeups count the times the app woke a sleeping core or took an interrupt, not thread switches.
- The chart is a QuickChart GET link that holds the whole chart, so it does not expire. Its numbers are the same medians as the table.

The calculations live in [`Scripts/Diagnostics/perf.py`](../../Scripts/Diagnostics/perf.py), and `Tests/RepositoryScripts/test_perf.py` checks them.
