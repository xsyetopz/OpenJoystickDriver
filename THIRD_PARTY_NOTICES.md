# Third-Party Notices

## GamepadMotionHelpers

The player-space and world-space gyro projection in `MotionProjection.swift` is adapted from [GamepadMotionHelpers][1], revision `39b578aacf34c3a1c584d8f7f194adc776f88055`.

MIT License

Copyright (c) 2020-2023 Julian "Jibb" Smart

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

[1]: https://github.com/JibbSmart/GamepadMotionHelpers/tree/39b578aacf34c3a1c584d8f7f194adc776f88055

## LiveKitWebRTC

The WebRTC bridge in `Tools/WebRTCBridge/` links [LiveKitWebRTC][2], the `livekit/webrtc-xcframework` package, pinned to 150.7871.03. The app, the service and `ojd` do not link it. The framework is a build of Google's WebRTC library, which has its own BSD-3-Clause license, reproduced below the package's MIT license. The package license is:

MIT License

Copyright (c) 2021 WebRTC SDKs

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

The Google WebRTC library, which the framework contains, is licensed as follows:

Copyright (c) 2011, The WebRTC project authors. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

- Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.

- Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in
  the documentation and/or other materials provided with the
  distribution.

- Neither the name of Google nor the names of its contributors may
  be used to endorse or promote products derived from this software
  without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

[2]: https://github.com/livekit/webrtc-xcframework/tree/150.7871.03

## SDL_GameControllerDB

The app ships the Mac OS X lines of [SDL_GameControllerDB][3], commit `07af1d50187e94c861c9f9f5d8a55b148f11306b`, as `sdl-gamecontrollerdb.txt`. The generator removes other platforms and the pads the catalog already records, and marks the file as altered. The database is under the zlib license:

Copyright (C) 1997-2025 Sam Lantinga <slouken@libsdl.org>

This software is provided 'as-is', without any express or implied
warranty.  In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
   claim that you wrote the original software. If you use this software
   in a product, an acknowledgment in the product documentation would be
   appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.

[3]: https://github.com/mdqinc/SDL_GameControllerDB/tree/07af1d50187e94c861c9f9f5d8a55b148f11306b

## flydigi-space-station-mac

The `04B4:2412` record follows the report layout in `docs/protocol.md` of [flydigi-space-station-mac][4], commit `649b9f36cbba80deb7e7ac11309615d44f382a8e`. No code is copied. The project is under the MIT license:

MIT License

Copyright (c) 2026 Uilton Lopes and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

[4]: https://github.com/uiltonlopes/flydigi-space-station-mac/tree/649b9f36cbba80deb7e7ac11309615d44f382a8e

## openflydigi

The frame and command facts for Flydigi vendor output come from `PROTOCOL.md` of [openflydigi][5], commit `11653507bbe4dc77f3c479c2a7aaebf25bbda995`. No code is copied. The author dedicated `PROTOCOL.md` to the public domain under CC0 1.0 Universal (<https://creativecommons.org/publicdomain/zero/1.0/legalcode>); the other files of that repository carry other licenses and are not used.

[5]: https://github.com/mkaliaha/openflydigi/tree/11653507bbe4dc77f3c479c2a7aaebf25bbda995

## wiiuse

The Wii Remote driver takes facts from [wiiuse][6], commit `e769bd73860a4f941bd110ebae5a790f968b71e3`: register addresses, report ids and sizes, cited by file and line in `openspec/changes/wii-remote/design.md`. No code is copied. wiiuse is under GPL-3.0-or-later, so OJD records only the facts and keeps none of its text.

[6]: https://github.com/wiiuse/wiiuse/tree/e769bd73860a4f941bd110ebae5a790f968b71e3
