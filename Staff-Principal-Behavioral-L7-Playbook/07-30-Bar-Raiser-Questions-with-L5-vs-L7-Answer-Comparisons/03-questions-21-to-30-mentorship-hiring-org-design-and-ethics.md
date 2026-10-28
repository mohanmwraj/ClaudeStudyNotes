# 07.3 · Questions 21–30: Mentorship, Hiring, Org Design and Ethics

> **Folder 07 · File 3 of 3.** Ten questions about the leverage an L7 has beyond their own technical work: growing engineers, raising the hiring bar, shaping how teams are organized, making an org more effective without headcount, protecting people, acting on ethical concerns, balancing users against short-term business interest, changing culture, and making yourself unnecessary.
>
> These are the questions where strong technical candidates most often run out of material. They map to Amazon's Hire and Develop the Best, Strive to be Earth's Best Employer, and Success and Scale Bring Broad Responsibility, and to Reilly's "leveling up" pillar. Questions are **original formulations**; the L7 answers are **three-minute illustrative composites**.

---

## 1. How to use this file

1. Write your own answer before reading the models.
2. Check people answers against the role boundary (05.3 §2.1): what you owned, and what a manager owned.
3. For Q27 and Q28 (ethics, users vs business), the answer must show **what you did**, not only what you believed. A principle with no action is not evidence.
4. Rehearse the probes in §4.

---

## 2. Hiring Committee Scoring Rubric (people, organization and ethics questions)

| Signal | Strong Hire at L7 | Down-level to L5 |
|---|---|---|
| **Growing people** | Sponsored engineers into Staff-scope ownership; named outcomes; people they grew now grow others | Mentored on own team; generic outcomes |
| **Hiring** | Changed a hiring outcome with evidence; improved how the org interviews | Interviewed; followed the rubric |
| **Org design** | Changed team boundaries or ownership to match the architecture and the work, with measured effect | Suggested process improvements |
| **Leverage without headcount** | Raised an org's output by removing work, waiting or coordination | Worked harder; asked for more people |
| **Protecting people** | Mechanisms for sustainable load and focus; said no on the team's behalf with alternatives | Shielded informally; absorbed work |
| **Ethics** | Raised a concern early, with specifics, to the right people; changed the outcome; knew where the escalation line was | Agreed it was wrong; took no action |
| **Users vs business** | Showed long-term business value of the user-protective option, and got it chosen | Stated a value; deferred |
| **Culture** | Changed a practice that persists without them | Organized events |
| **Succession** | Made themselves unnecessary; named owners now run it | "My team can't manage without me" |

---

## 3. Story Blueprints: the ten questions

### Q21 · "Who's the strongest engineer you've grown, and how did you do it?"

*Tests:* Sponsorship over mentoring (05.3 §3).

#### How an L5 tells it

> "I mentored a junior engineer who joined our team. I reviewed her code carefully, paired with her on hard problems, and answered her questions. She's now a strong mid-level engineer and has taken on bigger tasks."

#### How an L7 tells it

> "The strongest engineer I've grown is Tomas, who was a mid-level engineer on our reliability team when I met him. He was excellent at debugging and invisible outside his team, because all his work was reactive.
>
> I noticed he'd fixed the same class of bug, connection-pool exhaustion, in four different services. I asked him to write up the pattern, then asked him to present it at the architecture review, which he'd never attended. After that, I gave him a problem rather than a task: make connection-pool exhaustion impossible across the fleet. I told him I'd review his design but not change it, unless it touched another team's release process.
>
> He designed adaptive pool limits in our shared client library, with a dashboard showing every service's pool headroom. When a senior engineer from the payments team pushed back on a default, I stayed quiet in the meeting and debriefed with him afterwards. He worked out the compromise himself.
>
> Connection-pool incidents went from about one a month to none in the following year. I wrote his promotion case evidence with specific examples, and he was promoted to senior, then to Staff two years later. He now runs the reliability guild that I started, and two of the engineers he's sponsored have been promoted."

**What separates them:** the L7 grows someone through visibility and ownership of a Staff-shaped problem, withholds rescue at the hard moment, advocates with evidence, and the leverage is recursive.

### Q22 · "Tell me about a hiring decision where you disagreed with the rest of the panel."

*Tests:* Raising the bar (Bar Raiser behavior), evidence over impression.

#### How an L5 tells it

> "I interviewed a candidate who others liked, but I felt his coding was weak. I gave a 'no hire' and explained my concerns in the debrief. In the end the team decided not to hire him."

#### How an L7 tells it

> "We were hiring a senior engineer for a payments team, and the panel was enthusiastic about a candidate who'd been excellent in the system-design round and very likeable throughout. I was the most senior interviewer and had run the behavioral round.
>
> My concern was specific. In two of his three stories, when I asked what he personally had decided, the answers changed: first 'I designed it', later 'my lead designed it and I implemented the main parts'. And in his failure story, the cause was another team's change. Separately, each could be nerves. Together, they suggested he'd describe other people's work as his own, which on a payments team, where incident accountability matters, was a serious risk.
>
> In the debrief, I read out his exact words from my notes rather than my impression, and asked the panel whether anyone had evidence that would answer the concern. One interviewer realized she'd seen a similar pattern but hadn't written it down. The hiring manager decided not to proceed at senior, and offered an interview at the mid-level instead, where the ownership expectations matched his evidence.
>
> Afterwards, I proposed one change to our interview guidance: every behavioral interviewer asks at least one 'what did you personally decide' probe and records the verbatim answer. That's now in our rubric."

**What separates them:** the L7 disagreement is evidence-based and quoted verbatim, framed around the specific risk for the role, invites the panel to refute it, results in a calibrated outcome rather than a flat no, and improves the rubric.

### Q23 · "How have you improved the way your org interviews or hires?"

*Tests:* Hire and Develop at org scope; mechanisms.

#### How an L5 tells it

> "I'm an active interviewer. I've done over 100 interviews, and I created a new coding question that our team uses. I also helped onboard new interviewers by shadowing."

#### How an L7 tells it

> "Two years ago, our org's offer acceptance was fine, but six-month regretted attrition among senior hires was about twice the company average, and the exit interviews said the same thing: the job wasn't what the interviews had suggested. Our loops tested coding and algorithms; the job was mostly integrating and operating distributed services.
>
> I proposed changing the loop to match the work. I replaced one algorithms round with a practical debugging round, using a real anonymized incident from our systems, scored on approach rather than speed. I rewrote the system-design rubric so that 'operability' was a scored dimension. And I added a 30-minute conversation with an engineer from the team, not scored, where candidates could ask what the job was really like.
>
> I didn't impose it. I piloted it with two hiring managers for a quarter, calibrated the new rounds against our existing scores, and trained twelve interviewers. The pilot showed similar pass rates, better agreement between interviewers, and better candidate feedback, so the director adopted it org-wide.
>
> A year later, six-month regretted attrition for senior hires was in line with the company average, and the debugging round has been adopted by two other orgs. The interviewer training is now run by two engineers I trained."

**What separates them:** the L7 starts from an org-level outcome metric, diagnoses the mismatch between the loop and the job, pilots and calibrates before scaling, measures the result, and hands off the mechanism.

### Q24 · "Tell me about a time you changed how teams were organized or how work was divided."

*Tests:* Org design; Conway's law; influence over structure without authority.

#### How an L5 tells it

> "Our team was too big, so I suggested to my manager that we split into two sub-teams, one for frontend and one for backend. It made planning easier."

#### How an L7 tells it

> "Our checkout org had three teams split by layer: front end, APIs and data. Almost every feature needed all three, so every change was a three-team negotiation, and lead time for a typical feature was about six weeks. Conway's law was working against us: the architecture mirrored the layer split, so each layer had become a bottleneck for the others.
>
> I wasn't the decision-maker, since team structure belonged to the director, but I could make the case. I mapped a quarter of features against the teams involved and showed that 80% touched all three. Then I proposed reorganizing around customer journeys, cart, payment and order confirmation, each owning its journey end to end, with a small platform team for shared infrastructure. The idea came from Skelton and Pais's *Team Topologies*: stream-aligned teams plus a platform team.
>
> The director's concern was the transition: people would lose their teams and specializations. So I designed the move in two steps. First, journey ownership for new work only, for one quarter, with people staying in their teams. Then the reorganization, once the boundaries had been tested. I also worked through with each engineering manager which engineers would want which journeys.
>
> After two quarters, lead time for a typical feature fell from six weeks to under two, and cross-team dependencies per feature fell from three to about one. The architecture followed: each journey team split its parts of the monolith along its own boundary within the year."

**What separates them:** the L7 diagnoses the structure from data, names the principle (Conway's law, team topologies), respects the director's decision rights, designs a reversible transition with the people concerns addressed, and measures the effect on delivery and architecture.

### Q25 · "Describe a time you made a team or org more effective without adding people."

*Tests:* Frugality, leverage, removing waste.

#### How an L5 tells it

> "Our team was overloaded, so I automated some manual deployment steps and wrote scripts for common tasks. That saved everyone a few hours a week."

#### How an L7 tells it

> "Our data org of about 40 engineers was asked to deliver a set of new data products with no new headcount. When I measured where time went, using our ticket system and a short survey, about a third of engineering time went to ad-hoc data requests from business teams: one-off queries, extracts and 'can you check this number'.
>
> Most of those requests were repeats. I categorized six months of them and found that 60% fell into twelve patterns. I proposed a self-service layer: a curated set of twelve governed datasets with documented definitions, and a request process where a repeat request had to be answered by pointing to a dataset, or by creating one.
>
> The pushback came from business analysts, who worried about losing direct help. So I paired each business team with a named data engineer for an hour a week during the transition, and measured their time-to-answer.
>
> Within two quarters, ad-hoc request volume fell by about 55%, business teams' median time to an answer fell from three days to under an hour for covered questions, and the time freed let the org deliver the new data products without new headcount. The curated datasets are now owned by the analytics engineering team."

**What separates them:** the L7 measures where the org's time goes, finds a pattern-level fix, addresses the affected stakeholders' concern, and quantifies both the freed capacity and the effect on the people being served.

### Q26 · "Tell me about a time you protected your team from overload or distraction."

*Tests:* Strive to be Earth's Best Employer; saying no with alternatives; sustainable pace.

#### How an L5 tells it

> "Our team was getting a lot of requests from other teams and it was distracting. I started handling most of the requests myself so the team could focus on the project."

#### How an L7 tells it

> "After a reorganization, my platform team of eight became the owner of three internal services we hadn't built, while still committed to a major migration. Within a month, interrupt work, meaning support questions, small requests and incidents, had grown to about 40% of the team's time, and two engineers were working evenings to keep the migration on track.
>
> I didn't absorb it myself, which would have made me the bottleneck. I changed how interrupts reached the team. I created a weekly interrupt rotation: one engineer handled all incoming requests and incidents, so the other seven had protected time. I published a request policy, with what we'd do, what we wouldn't, and the expected response time, and for the three inherited services I listed every recurring request and either automated it or documented a self-service answer.
>
> I also went to the director with the numbers and asked for one thing: the migration's deadline moved by four weeks, because the reorganization had added work that the original plan didn't include. She agreed.
>
> Interrupts fell from 40% of team time to about 15% within two months, evening work stopped, and the migration landed on the revised date. The rotation model was adopted by two other platform teams. Nobody on the team left in the following year, which, given how that quarter had started, I count as the most important result."

**What separates them:** the L7 refuses to absorb, changes the system of interrupts, publishes a policy, removes recurring work, renegotiates the commitment upward with data, and measures well-being outcomes.

### Q27 · "Tell me about a time you saw something you believed was wrong. What did you do?"

*Tests:* Ethics, courage, escalation judgment; knowing the line where disagree-and-commit does not apply (02.1 §4.2).

#### How an L5 tells it

> "I noticed that our app was collecting more user data than it needed. I mentioned it to my manager, and he said legal had approved it. I wasn't sure it was right, but I let it go."

#### How an L7 tells it

> "Our growth team planned to use precise location data, collected for fraud detection, to target marketing notifications. The data had been collected under a privacy notice that said it was used for security. The plan had been approved by the growth director, and the launch was three weeks away.
>
> I believed it was wrong, and not just risky: users had given that data for one purpose, and we'd be using it for another without asking. I started with the growth director, privately, and explained my concern specifically: the stated purpose in our notice, the difference between the two uses, and the regulatory exposure in the regions where we operated. She disagreed: legal had reviewed the feature. When I asked, it turned out the review had been of the notification feature, not of the data source.
>
> This was a line where I wouldn't disagree and commit, and I told her so. I said I'd raise it with our privacy counsel, and invited her to come. We went together. The counsel agreed the purpose limitation applied, and recommended an explicit opt-in for marketing use of location.
>
> The feature launched four weeks later, with a consent screen and coarse city-level location rather than precise coordinates. About a third of users opted in, and the campaign still met its target. I also proposed, and the privacy team adopted, a data-use register: every dataset now records its permitted purposes, and new uses require a privacy review of the source."

**What separates them:** the L7 identifies the specific ethical issue, raises it directly first, discovers the gap in the earlier approval, states clearly that this is a line they won't commit across, escalates transparently and together, achieves an outcome that serves both users and the business, and leaves a mechanism.

### Q28 · "Tell me about a time you had to balance users' interests against the company's short-term interest."

*Tests:* Success and Scale Bring Broad Responsibility; Users First; long-term business framing.

#### How an L5 tells it

> "Our product team wanted to make the subscription cancellation flow longer to reduce churn. I didn't think it was good for users, so I raised it, but they went ahead. Churn went down a bit."

#### How an L7 tells it

> "Our subscriptions team proposed adding four extra screens to the cancellation flow, with retention offers and a 'call to cancel' option, to cut churn by an estimated 15%. I thought it would damage trust, but 'it's bad for users' wasn't going to win against a 15% churn reduction.
>
> So I made the long-term business case. I joined cancellation data with our support data and found that users who'd struggled to cancel had a much lower reactivation rate later, and they generated about three times as many support contacts and payment disputes. I also noted the increasing regulatory scrutiny of hard-to-cancel subscriptions in two of our markets.
>
> I proposed an alternative to the product director: one-click cancellation, with a single screen offering a pause option and a relevant discount, and a test against the four-screen version. She agreed to the test, on the condition that if the four-screen version won on 90-day revenue, it would ship. I accepted that condition.
>
> Over 90 days, the four-screen version reduced immediate churn more, but the one-screen version had higher reactivation, fewer disputes and better net revenue per canceling user. The one-screen flow shipped. The pause option, which the test showed many users preferred to canceling, became a feature in its own right."

**What separates them:** the L7 converts a value into a long-term business argument with data, proposes a user-respecting alternative, accepts a fair condition for the test, and lets evidence decide, with an outcome that served both.

### Q29 · "Describe a time you changed a culture or practice in your org."

*Tests:* Culture as mechanisms, persistence after you step back.

#### How an L5 tells it

> "Our team didn't write many design docs, so I started writing them for my projects and encouraged others to do the same. A few people started doing it too."

#### How an L7 tells it

> "Our org of about 120 engineers made most architectural decisions in meetings, and six months later nobody could remember why. We'd revisited the same database choice three times in a year, at a real cost in time each round.
>
> I didn't try to mandate documentation. I made the decision record the cheapest way to get a decision. I introduced a one-page architecture decision record template, based on Nygard's, and offered to run a weekly 30-minute decision review where any team could bring a record and get a decision from the senior engineers that week. Before that, getting a cross-team decision took weeks of meetings.
>
> I wrote the first ten records myself, for decisions that had already been made, so people could see the format with real content, and I made the record library searchable from our developer portal.
>
> Within a year, the org had about 150 records, the weekly review had a rotating chair from four teams, and the repeated database debate hadn't come back, because the record showed what had been considered. New engineers' onboarding surveys started citing the records as the most useful onboarding material. I stopped attending the review after the first six months, and it still runs."

**What separates them:** the L7 changes culture by making the desired behavior the easiest path, seeds it with real examples, gives it a forum and an incentive (faster decisions), measures adoption and effect, and steps out while it continues.

### Q30 · "Tell me about a time you made yourself unnecessary."

*Tests:* Succession, leverage, the end state of L7 work.

#### How an L5 tells it

> "I documented everything about the system I built, so that when I moved to another project, the team could maintain it without me. They still ask me questions sometimes."

#### How an L7 tells it

> "For about two years, I was the person our streaming platform depended on. I'd designed it, I approved every schema change, and I was the escalation point for any incident. That felt like success until I looked at it from the org's side: four teams' roadmaps depended on my availability, and when I was on holiday, schema changes waited.
>
> I set a goal for myself: in six months, the platform should run for a month without me. I wrote down every decision I was making, and sorted them into those that could be automated, delegated or eliminated. Schema approvals became a compatibility check in CI, with a human review only for breaking changes. Incident escalation moved to a rotation of four senior engineers I paired with for two months. Design authority for the platform went to Lena, a senior engineer on the platform team, whom I'd been coaching for that role.
>
> The test came when I took a month away. The platform had one significant incident, which the rotation handled, and Lena approved two design changes I wouldn't have thought of. Schema-change lead time fell from about four days, which was mostly waiting for me, to under an hour.
>
> Lena was promoted to Staff the next cycle, and I moved on to a new cross-org problem. That move was only possible because the platform no longer needed me, which is the point of the work."

**What separates them:** the L7 recognizes their own indispensability as a risk, sets a measurable goal, systematically automates, delegates or eliminates their decisions, grows a named successor, tests it with real absence, and reports the measured effect.

---

## 4. Bar-Raiser Follow-Up Chains

| Q | Probe | Tests | Owner's answer shape |
|---|---|---|---|
| **21** | "What did you give up so he could grow?" | Sponsorship | A Staff-shaped problem, and the review spotlight |
| | "When did you hold back?" | Restraint | The payments pushback meeting |
| | "What did you write in his promotion case?" | Advocacy | Specific examples |
| **22** | "How do you know it wasn't nerves?" | Fairness | The pattern across stories, and the invitation to refute |
| | "What did the hiring manager decide?" | Decision rights | A level-calibrated alternative |
| | "What changed afterwards?" | Mechanism | The verbatim-probe rubric item |
| **23** | "Why change the loop?" | Diagnosis | Attrition and exit-interview evidence |
| | "How did you know the new rounds were fair?" | Rigor | Pilot calibration against existing scores |
| | "Who runs it now?" | Leverage | Two trained engineers |
| **24** | "Whose decision was the reorganization?" | Role boundary | The director's |
| | "What did people lose?" | Empathy | Teams and specializations, and how it was handled |
| | "How did the architecture change?" | Conway's law | Journey teams split the monolith on their boundaries |
| **25** | "How did you know where time went?" | Measurement | Tickets plus survey |
| | "What did business teams lose?" | Stakeholders | Direct help, offset by named pairing |
| | "What did the freed time produce?" | Result | The new data products without headcount |
| **26** | "Why not handle the requests yourself?" | Hero trap | It makes the candidate the bottleneck |
| | "What did you ask the director for?" | Upward negotiation | Four weeks, with data |
| | "How do you know the team was better off?" | Well-being | Evening work stopped; no attrition |
| **27** | "Why wasn't this a disagree-and-commit?" | The line | Purpose limitation; users' consent |
| | "Did you go around the director?" | Transparency | Told her first, invited her along |
| | "What if counsel had disagreed with you?" | Judgment | Accept the legal view, and record the concern |
| **28** | "Why not just argue it was wrong?" | Influence | The value alone wouldn't win; data would |
| | "What condition did you accept?" | Fairness | 90-day revenue decides |
| | "What if the four-screen version had won?" | Commitment and the line | Ship it, unless it crossed a legal or ethical line |
| **29** | "Why would teams write records?" | Incentive | Faster decisions |
| | "What did you do first?" | Seeding | Wrote ten real records |
| | "Does it still run without you?" | Persistence | Yes, rotating chair |
| **30** | "How did you know you were a bottleneck?" | Self-awareness | Roadmap dependencies; waiting time |
| | "What did you automate, delegate and eliminate?" | Method | Each category, with examples |
| | "What happened during your absence?" | Evidence | The incident and Lena's decisions |

---

## 5. Checklist

- [ ] Q21: a named person, what you gave up for them, where you held back, and what they do now.
- [ ] Q22–Q23: evidence-based hiring judgment, and a mechanism that improved the loop.
- [ ] Q24: an org-design change grounded in data, respecting who had decision rights.
- [ ] Q25–Q26: leverage without headcount; protection through mechanisms, not absorption.
- [ ] Q27–Q28: actions, not beliefs; the escalation line stated; a mechanism afterwards.
- [ ] Q29: a practice that persists after you stepped back.
- [ ] Q30: your own indispensability treated as a risk, and removed.

## 6. References

- Matthew Skelton and Manuel Pais, *Team Topologies* (IT Revolution, 2019): stream-aligned and platform teams, the basis of Q24.
- Melvin Conway, "How Do Committees Invent?", *Datamation*, April 1968: Conway's law. <https://www.melconway.com/Home/Committees_Paper.html>
- Michael Nygard, "Documenting Architecture Decisions" (2011): the template behind Q29. <https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions>
- In this KB: [05.3 Sponsorship and feedback](../05-Production-Outages-Mistakes-and-Psychological-Safety/03-delivering-hard-feedback-handling-low-performers-and-mentoring-l5s.md) · [02.1 Hire and Develop; Earth's Best Employer](../02-Company-Specific-Behavioral-Blueprints-Amazon-Google-Meta/01-amazon-16-leadership-principles-l6-l7-bar-raiser-deep-dive.md) · [07.1 Questions 1–10](01-questions-01-to-10-conflict-pushback-and-disagree-and-commit.md) · [07.2 Questions 11–20](02-questions-11-to-20-ambiguity-vision-failure-and-missed-deadlines.md)
