# PR #4: chore(deps): bump softprops/action-gh-release from 2 to 3

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/pull/4
- **State:** MERGED
- **Draft:** False
- **Author:** app/dependabot
- **Created:** 2026-05-12T18:47:51Z
- **Updated:** 2026-05-12T19:46:50Z
- **Closed:** 2026-05-12T19:46:47Z
- **Merged:** 2026-05-12T19:46:47Z

## Description

Bumps [softprops/action-gh-release](https://github.com/softprops/action-gh-release) from 2 to 3.
<details>
<summary>Release notes</summary>
<p><em>Sourced from <a href="https://github.com/softprops/action-gh-release/releases">softprops/action-gh-release's releases</a>.</em></p>
<blockquote>
<h2>v3.0.0</h2>
<p><code>3.0.0</code> is a major release that moves the action runtime from Node 20 to Node 24.
Use <code>v3</code> on GitHub-hosted runners and self-hosted fleets that already support the
Node 24 Actions runtime. If you still need the last Node 20-compatible line, stay on
<code>v2.6.2</code>.</p>
<h2>What's Changed</h2>
<h3>Other Changes 🔄</h3>
<ul>
<li>Move the action runtime and bundle target to Node 24</li>
<li>Update <code>@types/node</code> to the Node 24 line and allow future Dependabot updates</li>
<li>Keep the floating major tag on <code>v3</code>; <code>v2</code> remains pinned to the latest <code>2.x</code> release</li>
</ul>
<h2>v2.6.2</h2>
<!-- raw HTML omitted -->
<h2>What's Changed</h2>
<h3>Other Changes 🔄</h3>
<ul>
<li>chore(deps): bump picomatch from 4.0.3 to 4.0.4 by <a href="https://github.com/dependabot"><code>@​dependabot</code></a>[bot] in <a href="https://redirect.github.com/softprops/action-gh-release/pull/775">softprops/action-gh-release#775</a></li>
<li>chore(deps): bump brace-expansion from 5.0.4 to 5.0.5 by <a href="https://github.com/dependabot"><code>@​dependabot</code></a>[bot] in <a href="https://redirect.github.com/softprops/action-gh-release/pull/777">softprops/action-gh-release#777</a></li>
<li>chore(deps): bump vite from 8.0.0 to 8.0.5 by <a href="https://github.com/dependabot"><code>@​dependabot</code></a>[bot] in <a href="https://redirect.github.com/softprops/action-gh-release/pull/781">softprops/action-gh-release#781</a></li>
</ul>
<p><strong>Full Changelog</strong>: <a href="https://github.com/softprops/action-gh-release/compare/v2...v2.6.2">https://github.com/softprops/action-gh-release/compare/v2...v2.6.2</a></p>
<h2>v2.6.1</h2>
<p><code>2.6.1</code> is a patch release focused on restoring linked discussion thread creation when
<code>discussion_category_name</code> is set. It fixes <code>[#764](https://github.com/softprops/action-gh-release/issues/764)</code>, where the draft-first publish flow
stopped carrying the discussion category through the final publish step.</p>
<p>If you still hit an issue after upgrading, please open a report with the bug template and include a minimal repro or sanitized workflow snippet where possible.</p>
<h2>What's Changed</h2>
<h3>Bug fixes 🐛</h3>
<ul>
<li>fix: preserve discussion category on publish by <a href="https://github.com/chenrui333"><code>@​chenrui333</code></a> in <a href="https://redirect.github.com/softprops/action-gh-release/pull/765">softprops/action-gh-release#765</a></li>
</ul>
<h2>v2.6.0</h2>
<p><code>2.6.0</code> is a minor release centered on <code>previous_tag</code> support for <code>generate_release_notes</code>,
which lets workflows pin GitHub's comparison base explicitly instead of relying on the default range.
It also includes the recent concurrent asset upload recovery fix, a <code>working_directory</code> docs sync,
a checked-bundle freshness guard for maintainers, and clearer immutable-prerelease guidance where
GitHub platform behavior imposes constraints on how prerelease asset uploads can be published.</p>
<p>If you still hit an issue after upgrading, please open a report with the bug template and include a minimal repro or sanitized workflow snippet where possible.</p>
<h2>What's Changed</h2>
<!-- raw HTML omitted -->
</blockquote>
<p>... (truncated)</p>
</details>
<details>
<summary>Changelog</summary>
<p><em>Sourced from <a href="https://github.com/softprops/action-gh-release/blob/master/CHANGELOG.md">softprops/action-gh-release's changelog</a>.</em></p>
<blockquote>
<h2>0.1.13</h2>
<ul>
<li>fix issue with multiple runs concatenating release bodies <a href="https://redirect.github.com/softprops/action-gh-release/pull/145">#145</a></li>
</ul>
</blockquote>
</details>
<details>
<summary>Commits</summary>
<ul>
<li><a href="https://github.com/softprops/action-gh-release/commit/b4309332981a82ec1c5618f44dd2e27cc8bfbfda"><code>b430933</code></a> release: cut v3.0.0 for Node 24 upgrade (<a href="https://redirect.github.com/softprops/action-gh-release/issues/670">#670</a>)</li>
<li><a href="https://github.com/softprops/action-gh-release/commit/c2e35e05a74208bafbfcbdae5ebc9da7236e980f"><code>c2e35e0</code></a> chore(deps): bump the npm group across 1 directory with 7 updates (<a href="https://redirect.github.com/softprops/action-gh-release/issues/783">#783</a>)</li>
<li>See full diff in <a href="https://github.com/softprops/action-gh-release/compare/v2...v3">compare view</a></li>
</ul>
</details>
<br />


[![Dependabot compatibility score](https://dependabot-badges.githubapp.com/badges/compatibility_score?dependency-name=softprops/action-gh-release&package-manager=github_actions&previous-version=2&new-version=3)](https://docs.github.com/en/github/managing-security-vulnerabilities/about-dependabot-security-updates#about-compatibility-scores)

Dependabot will resolve any conflicts with this PR as long as you don't alter it yourself. You can also trigger a rebase manually by commenting `@dependabot rebase`.

[//]: # (dependabot-automerge-start)
[//]: # (dependabot-automerge-end)

---

<details>
<summary>Dependabot commands and options</summary>
<br />

You can trigger Dependabot actions by commenting on this PR:
- `@dependabot rebase` will rebase this PR
- `@dependabot recreate` will recreate this PR, overwriting any edits that have been made to it
- `@dependabot show <dependency name> ignore conditions` will show all of the ignore conditions of the specified dependency
- `@dependabot ignore this major version` will close this PR and stop Dependabot creating any more for this major version (unless you reopen the PR or upgrade to it yourself)
- `@dependabot ignore this minor version` will close this PR and stop Dependabot creating any more for this minor version (unless you reopen the PR or upgrade to it yourself)
- `@dependabot ignore this dependency` will close this PR and stop Dependabot creating any more for this dependency (unless you reopen the PR or upgrade to it yourself)


</details>

## Files

- `.github/workflows/release.yml` (+1/-1, MODIFIED)

## Commits

- `924a4200c0b0` chore(deps): bump softprops/action-gh-release from 2 to 3

## Conversation

_No comments._

## Reviews

_No reviews._

## Inline review comments

_No inline review comments._

## Patch

[Full patch](pull-4.patch)
