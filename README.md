# HDAUniversal Bootloader Injector
The goal of this project is to enable macOS SIP.

Download [HDAUniversal Bootloader Injector](https://github.com/chris1111/HDAUniversal-Bootloader-Injector/archive/refs/heads/main.zip) the Project folder then run `HDAUniversal Injector.tool`

SIP	No changes — works fully enabled

NOTE: Dont replace the kext in `ORIG-HDAUniversal`  with a newer version, it will not work!

Why new version will not work: Latest HDAUniversal build IMPORTS 3 IOGraphics symbol(s)!
The prelinker cannot resolve IOGraphicsFamily (not in the boot KC)



### The script's operations, in execution order:
1. The source material
Takes the pristine HDAUniversal.kext from the shipped ORIG-HDAUniversal/ folder (untouched original from MaLd0n)
2. The provider — copies + patches Apple's IOAudioFamily:

OPERATION | DETAIL
-- | --
Source | /S/L/E copy if real, else KDK auto-download (matching build, from Dortania)
Thin | lipo -thin x86_64 (drops arm64e slice — the safe-patch prerequisite)
THE ALIAS (binary) | com.apple.iokit.IOAudioFamily → net.olarila.IOAudioFamily — 29 chars → 25 chars + 4 NULs, byte-safe -0777 perl, length-preserving (the Mach-O offset law)
THE ALIAS (plist) | Same rename in CFBundleIdentifier

<p class="p7"><span class="s1"></span><br></p>
<p class="p1"><span class="s1">Why this creates the injection magic:</span></p>
<ol class="ol1">
<li class="li3"><span class="s1">The renamed provider coexists with Apple's stock IOAudioFamily (no identifier collision)</span></li>
<li class="li3"><span class="s1">HDAUniversal's dependency now points at a kext that can be injected (the alias lives on the ESP with the drivers)</span></li>
<li class="li3"><span class="s1">The booter's prelinker resolves: provider first (OSBundleRequired=Root + personality) </span><span class="s7">→</span><span class="s1"> driver second </span><span class="s7">→</span><span class="s1"> the chain that was impossible since 2020 closes</span></li>
<li class="li3"><span class="s1">HDAUniversal's runtime then binds to the aliased family's classes — which are Apple's own code, just renamed</span></li>
</ol>
<p class="p4"><span class="s1"></span><br></p>
<p class="p8"><span class="s1">One sentence summary: the script renames the IOAudioFamily dependency-pair (provider identifier + driver's pointer to it) so the pair can travel together through the bootloader — everything else in both kexts stays pristine.</span></p>

<p class="p8"><span class="s1">3 renames and 2 signatures.🏗️</span></p>

### Credit: 

chris1111 — Coder

MaLd0n - [Developer](https://olarila.com/profile/2-mald0n/)
