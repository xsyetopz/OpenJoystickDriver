# #8: Steam Controller Support

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/8
- **State:** OPEN
- **Author:** julesbravo
- **Created:** 2026-06-03T23:26:22Z
- **Updated:** 2026-08-25T16:22:15Z
- **Closed:** —
- **Labels:** enhancement, help wanted

## Report

Are there any plans to support Steam Controller? Lots of people are running into issues with certain games not recognizing the controller on Mac, this seems like it could be a solution.

## Comments

### xsyetopz — 2026-06-05T19:53:11Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4634991990)

I wish I could, but I don't have a physical controller to test on. Such matter is more of an assumption based on "vibes" if there's no user to *actually* test the hardware. If y'have a Steam Controller, or know a macOS user that has one, maybe we can get in contact to try it out?

### xsyetopz — 2026-06-05T19:56:40Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4635017223)

HOWever, I found that Steam Controller on Linux is supported under the [hid-stream.c](https://github.com/torvalds/linux/blob/master/drivers/hid/hid-steam.c) file, so perhaps creating a pre-release with this could help, maybe more-so if I add a few extra controller ends && mark them as experimental && in need of physical devices to test on. That would help immensely in the long run!

### julesbravo — 2026-06-05T19:57:01Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4635019456)

I have both.

### xsyetopz — 2026-06-05T20:05:51Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4635083646)

> I have both.

This'll be great, then!

I already dug out some external sources to check out.

### julesbravo — 2026-06-05T20:18:02Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4635186400)

Awesome. I'll be on vacation without access to said Mac for next 2 weeks, but as soon as I get back I'll be more than happy to help test. I'm including a screenshot of the information that Steam has said so far about the issue.

<img width="1319" height="2200" alt="Image" src="https://github.com/user-attachments/assets/5bca26b4-ab71-4ce3-ae42-1f0954dab0ae" />

### xsyetopz — 2026-06-05T20:29:00Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4635270572)

> Awesome. I'll be on vacation without access to said Mac for next 2 weeks, but as soon as I get back I'll be more than happy to help test. I'm including a screenshot of the information that Steam has said so far about the issue.
>
> <img alt="Image" width="1199" height="2000" src="https://private-user-images.githubusercontent.com/194692/603690086-5bca26b4-ab71-4ce3-ae42-1f0954dab0ae.png">

I don't know how much Steam or certain communities allow for LLM-generated code, but maybe they could endorse use of OJD for Steam && SDL-based apps? It seems like a solution that there wasn't anything for since 2015 (Enjoyable)

Works well for me, && the engine is there, so... all OJD needs is community assistance, && it could really take off for us macOS users whole!

### julesbravo — 2026-06-05T20:52:45Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4635441539)

The community is split on it, but I think they will take it if it’s a
solution. That is actually how I found your project I was looking to see if
anybody built any drivers themselves that would support it. Either by hand
or through agenetic methods. If I didn’t find anything, I was going to take
a stab at it with Claude, but I am a web developer by trade and have no
idea about drivers.

On Fri, Jun 5, 2026 at 3:29 PM Krystian J. ***@***.***> wrote:

> *xsyetopz* left a comment (xsyetopz/OpenJoystickDriver#8)
> <https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4635270572>
>
> Awesome. I'll be on vacation without access to said Mac for next 2 weeks,
> but as soon as I get back I'll be more than happy to help test. I'm
> including a screenshot of the information that Steam has said so far about
> the issue.
> [image: Image]
> <https://private-user-images.githubusercontent.com/194692/603690086-5bca26b4-ab71-4ce3-ae42-1f0954dab0ae.png>
>
> I don't know how much Steam or certain communities allow for LLM-generated
> code, but maybe they could endorse use of OJD for Steam && SDL-based apps?
> It seems like a solution that there wasn't anything for since 2015
> (Enjoyable)
>
> Works well for me, && the engine is there, so...
>
> —
> Reply to this email directly, view it on GitHub
> <https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4635270572>,
> or unsubscribe
> <https://github.com/notifications/unsubscribe-auth/AABPRBG77F5DBPUMKCEWVCT46MUSDAVCNFSM6AAAAACZZPTKEWVHI2DSMVQWIX3LMV43OSLTON2WKQ3PNVWWK3TUHM2DMMZVGI3TANJXGI>
> .
> You are receiving this because you authored the thread.Message ID:
> ***@***.***>
>

### xsyetopz — 2026-06-05T20:56:01Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4635460678)

> The community is split on it, but I think they will take it if it’s a
> solution. That is actually how I found your project I was looking to see if
> anybody built any drivers themselves that would support it. Either by hand
> or through agenetic methods. If I didn’t find anything, I was going to take
> a stab at it with Claude, but I am a web developer by trade and have no
> idea about drivers.
> […](#)

I needed a solution myself when I moved from Windows, && this didn't just take a little bit. Apparently it took months, && 1/4th of it was prototyping, but the end result... *AMAAAAZING*.

### julesbravo — 2026-06-05T21:04:34Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4635512949)

I'm kind of surprised Steam's fix isn't just a way to have it emulate an xbox controller in the configuration.

### xsyetopz — 2026-06-05T22:57:16Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4636232584)

Try this [0.5.0-alpha.1](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.1) pre-release, then follow the [Steam Controller Hardware Test](https://github.com/xsyetopz/OpenJoystickDriver/blob/main/docs/REQUEST/STEAM_CONTROLLER_HARDWARE_TEST_REQUEST.md) request.

Thank you!

### julesbravo — 2026-06-06T00:14:37Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4636552263)

I don't think this is working quite right. When I do the test in the Wired Controller Capture section I don't get any `REPORT` lines. I think that Mac is still accepting the input as a generic controller while Steam is not running because I'm seeing input in the terminal.

```
OJD_USE_LOCAL_SWIFTUSB=1 swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1102 --seconds 30

[1/1] Planning build
Building for debugging...
ld: warning: building for macOS-11.0, but linking with dylib '/opt/homebrew/opt/libusb/lib/libusb-1.0.0.dylib' which was built for newer version 26.0
[81/81] Applying OpenJoystickDriverHIDTool
Build of product 'OpenJoystickDriverHIDTool' complete! (4.30s)
Monitoring 0 device(s), VID:0x28de PID:0x1102, 30s

^[	^[^[[B^[[A^[[D^[[CSUMMARY values=0 reports=0
```

### julesbravo — 2026-06-06T00:16:20Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4636557880)

Just noting that I did have Steam completely quit out when I ran the test. In the activity monitor, there was no sign of it.

### xsyetopz — 2026-06-06T09:40:00Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4638144582)

I made small changes within `main.swift`, && the REQUEST document. It'd help to try again (would've been easier if I owned the controller...)

Try [again with 0.5.0-alpha.3](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.3).

### julesbravo — 2026-06-06T13:05:53Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4638707240)

Sorry man I have left on my trip. Let’s circle back when I return.

On Sat, Jun 6, 2026 at 4:40 AM Krystian J. ***@***.***> wrote:

> *xsyetopz* left a comment (xsyetopz/OpenJoystickDriver#8)
> <https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4638144582>
>
> I made small changes within main.swift, && the REQUEST document. It'd
> help to try again (would've been easier if I owned the controller...)
>
> Try again with 0.5.0-alpha.2
> <https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.2>
> .
>
> —
> Reply to this email directly, view it on GitHub
> <https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4638144582>,
> or unsubscribe
> <https://github.com/notifications/unsubscribe-auth/AABPRBD47WBLNJ3TQ2FE2IL46PRINAVCNFSM6AAAAACZZPTKEWVHI2DSMVQWIX3LMV43OSLTON2WKQ3PNVWWK3TUHM2DMMZYGE2DINJYGI>
> .
> You are receiving this because you authored the thread.Message ID:
> ***@***.***>
>

### xsyetopz — 2026-06-17T21:08:13Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4735480532)

Hello! It's been 2 weeks. Are y'back yet?

### julesbravo — 2026-06-17T21:33:37Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4735744812)

I get back Sunday. Don’t worry I haven’t forgotten I’m excited to see how
we can get this to work.

On Wed, Jun 17, 2026 at 3:08 PM Krystian J. ***@***.***>
wrote:

> *xsyetopz* left a comment (xsyetopz/OpenJoystickDriver#8)
> <https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4735480532>
>
> Hello! It's been 2 weeks. Are y'back yet?
>
> —
> Reply to this email directly, view it on GitHub
> <https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4735480532>,
> or unsubscribe
> <https://github.com/notifications/unsubscribe-auth/AABPRBFSWSRYGOV6KTDYVV35AMCFFAVCNFSNUABGKJSXA33TNF2G64TZHMYTCNZSGEYTQOJZGM5US43TOVSTWNBVHA2DIMBWHAYDNILWAI>
> .
> You are receiving this because you authored the thread.Message ID:
> ***@***.***>
>

### xsyetopz — 2026-06-17T21:48:19Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4735839523)

> I get back Sunday. Don’t worry I haven’t forgotten I’m excited to see how
> we can get this to work.
> […](#)

Okay! I wish I could set up like a global community for me && all the people interested in my projects && off-project stuffs, so that screenshots, private test-this-for-me-please builds && other stuff could be knocked down easily. Any ideas?

### julesbravo — 2026-06-17T21:55:39Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4735884791)

Discord?

On Wed, Jun 17, 2026 at 3:48 PM Krystian J. ***@***.***>
wrote:

> *xsyetopz* left a comment (xsyetopz/OpenJoystickDriver#8)
> <https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4735839523>
>
> I get back Sunday. Don’t worry I haven’t forgotten I’m excited to see how
> we can get this to work.
> … <#m_5811320886217926504_>
>
> Okay! I wish I could set up like a global community for me && all the
> people interested in my projects && off-project stuffs, so that
> screenshots, private test-this-for-me-please builds && other stuff could be
> knocked down easily. Any ideas?
>
> —
> Reply to this email directly, view it on GitHub
> <https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4735839523>,
> or unsubscribe
> <https://github.com/notifications/unsubscribe-auth/AABPRBHYTPZ6O27GDQTNY2D5AMG3TAVCNFSNUABGKJSXA33TNF2G64TZHMYTCNZSGEYTQOJZGM5US43TOVSTWNBVHA2DIMBWHAYDNILWAI>
> .
> You are receiving this because you authored the thread.Message ID:
> ***@***.***>
>

### xsyetopz — 2026-06-17T22:15:07Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-4736009109)

> Discord?
> […](#)

I initially had a discord server, but people didn't really use it, so I deleted it. I may bring it back soon...

### xsyetopz — 2026-08-25T16:22:15Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/8#issuecomment-5413412717)

Try [0.5.0-beta.1](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-beta.1) and tell me if it works!
