# Exam-Day Checklist (Wednesday 21 Oct 2026)

Based on the LF Candidate Requirements, Taking the Exam and FAQ pages (checked 17 Oct 2026). A failed check-in costs you the attempt, so do the Tuesday items on Tuesday.

## Tuesday evening (T−1 day)
- [ ] **Run the PSI Online Proctoring System Check** on the exact computer, network and room you will use (linked from the LF Candidate Requirements page and your exam checklist)
- [ ] **ID**: a valid, unexpired, government-issued, **original physical** ID (no photocopy or electronic ID) with your **name, photo and signature**. First and last name must **exactly match** the verified name on your LF exam checklist.
- [ ] Computer: personal device preferred (work devices often block the secure browser). **No virtual machines.** Laptop plugged into power.
- [ ] Ideally create a fresh OS admin profile with rights to install apps and stop processes; log in with it for the exam.
- [ ] **One active monitor only** (dual monitors are not supported). 15"+ at 1920×1080 is recommended.
- [ ] Webcam you can **move** to scan the room; microphone tested.
- [ ] Network: wired if possible. Ask others not to stream or download. Turn off file sync/torrent clients and VPNs. On an employer network, WebRTC streaming and HTTPS to AWS S3 must not be blocked.
- [ ] Room: walled and private, door closed, nobody else present, no printouts on the walls, no bright light or window behind you.
- [ ] Desk: **completely clear** (no paper, pens, phones, electronics, and nothing under the desk such as bins).
- [ ] Re-read the [Important Instructions page](https://docs.linuxfoundation.org/tc-docs/certification/tips-cka-and-ckad) for last-minute changes (Kubernetes version, tools).
- [ ] Sleep.

## Exam day, before launch
- [ ] Morning warm-up from memory (≤ 30 min, no new topics): NetworkPolicy + DNS egress, CronJob, probes, securityContext + capabilities, canary, `helm upgrade` + `rollback`, Role/RoleBinding + `auth can-i`
- [ ] Reboot the computer so at least 50% of RAM is free. Close every other app and browser window. Pause antivirus scanning and firewall pop-ups if you can.
- [ ] Water and phone out of the room/reach; the LF pages don't promise breaks, so plan for 2 hours straight.
- [ ] **Launch up to 30 minutes early** with "Take Exam" in My Portal. The PSI Secure Browser installs on first launch; depending on proctor availability you may wait until your start time.
- [ ] Check-in: accept the agreement, upload an ID photo, take a selfie, then do a live room/desk scan with the Check-In Specialist. The wait for a proctor should not exceed 15 minutes.
- [ ] **Hard deadline: start no later than 30 minutes after your scheduled time.** Missing it is a no-show, with no refund and no reschedule.

## First 2 minutes inside the exam
- [ ] Resize the Content Panel and font (+/−) so task text and terminal are both readable
- [ ] Open Firefox to kubernetes.io/docs once, so it's ready
- [ ] Remember: every task → `ssh <host>` → work → verify → `exit`
- [ ] On each host, only if useful: `export do="--dry-run=client -o yaml"`; one-line `~/.vimrc`

## During the exam
- [ ] Three-pass plan: quick wins first, flag anything that runs over ~6–8 minutes ([strategy](04-exam-strategy-and-time-management.md))
- [ ] Watch the timer alerts at 30 / 15 / 5 minutes left. At 10 minutes, stop starting long tasks and verify instead.
- [ ] Connection drop? Relaunch from the PSI dashboard's "Access" button (or reopen the PSI Secure Browser) and redo self check-in. **The timer is not paused**, which is why a stable network matters.
- [ ] Finish with **"End Exam"**, then **"End Session"**

## After the exam
- [ ] Score report by email **within 24 hours** (barring exceptions)
- [ ] Didn't pass? Your registration includes **one retake** when eligible. Use the score report's domain breakdown with this kit's chapters and mock exams to target the gap.
- [ ] Passed? Certification is valid for **2 years**. Note the renewal date.
