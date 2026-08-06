<!-- claims-lint:disable -->
# Evidence and Methods

This page explains what Amblyo does, what research it draws on, and — just as
importantly — what that research does not say about Amblyo.

We would rather be honest with you than impressive.

---

## The short version

Amblyo is a training app. It is not a medical device and it is not a treatment.
It does not diagnose, treat, cure or prevent any condition.

The exercises are modelled on methods that appear in published vision research.
**Those studies tested other products and laboratory tasks. Amblyo itself has
not been studied.** Nobody has run a trial on this app, and until somebody does,
you should treat it as structured practice — not as therapy.

---

## Evidence levels

Every exercise in Amblyo carries a badge. Here is what each one means.

### Level A — randomised controlled trials

This type of exercise has been tested in randomised controlled trials in people
with amblyopia. In our app, that means the binocular exercises: tasks where each
eye sees a different image at different contrast, and the task can only be
completed when both eyes contribute.

What the research shows: contrast-rebalanced binocular viewing has been compared
against patching in children in several randomised trials, with broadly
comparable short-term results at lower time cost. Two purpose-built systems
using this principle have regulatory clearance in the United States as
prescription medical devices.

What it does not show: anything about Amblyo. Those systems are prescribed,
supervised, and were tested with specific content and dosing. We are none of
those things.

### Level B — perceptual learning research

This type of exercise comes from perceptual learning studies — repeated practice
on a precise visual judgement, such as which way a striped patch is tilted, or
whether two lines are aligned.

What the research shows: adults with amblyopia have shown measurable
improvements on trained tasks after repeated sessions, and some studies report
improvements that carry over to letter charts. This is the body of work that
challenged the old idea that nothing can change after childhood.

What it does not show: how much of that transfers to everyday seeing, how long
it lasts, or anything about this app. Most of these studies are small, and few
are randomised.

### Level C — standard optometric practice

Eye-movement, focusing and fusion exercises used in optometric vision therapy —
pursuits, saccades, vergence work, anti-suppression tasks.

What the research shows: these are established clinical practice, with the
strongest trial evidence in convergence insufficiency rather than amblyopia.

What it does not show: strong published evidence for amblyopia specifically. We
include them because they are useful practice and people expect them, and we
label them honestly rather than dressing them up.

### What we left out

There is a category of popular "eye exercise" content — colour flashing, palming,
eye yoga, staring at moving dots to "exercise the eye muscle" — with no credible
supporting evidence. Amblyopia is a condition of visual development in the brain,
not weak eye muscles, so exercising the muscles has no mechanism to work through.

**None of that is in this app**, even though some of it is popular and would have
been easy to include.

---

## How the difficulty adapts

Amblyo uses a three-down / one-up adaptive staircase, a standard psychophysical
method. In plain terms: after three correct answers in a row it makes the task
slightly harder; after one wrong answer it makes it slightly easier. Over a
session this settles at the difficulty where you are getting roughly four out of
five correct — hard enough to be worth doing, not so hard that it is
discouraging.

The "training score" you see is an estimate of that settling point, averaged over
the last several reversals. It runs separately for each exercise and each eye.

Reference for the method: Levitt, H. (1971), *Transformed up-down methods in
psychoacoustics*, Journal of the Acoustical Society of America.

---

## How the screen is calibrated

A stimulus is only meaningful if we know how large it appears to your eye. That
depends on the physical size of your screen and how far away you sit — neither of
which iOS reports.

So Amblyo looks up your device's screen density, asks how far away you sit, and
optionally lets you verify the screen size by matching an on-screen rectangle to
a real bank card. From those, it computes visual angle directly:

    size = 2 × distance × tan(angle ÷ 2)

If you change your viewing distance, the numbers change meaning. Try to be
roughly consistent — it matters more than being exact.

---

## What the scores are and are not

**The scores in Amblyo are training scores, not clinical measurements.**

They are computed on a consumer screen, at an uncontrolled distance, in
uncontrolled lighting, with no clinical calibration. They are useful for watching
your own practice change over weeks. They cannot tell you your visual acuity, and
they cannot replace an eye examination.

When the data does not show a clear change, Amblyo says so rather than
manufacturing an encouraging trend. If nothing changes over eight weeks, the app
will suggest you speak to an eye care professional — because at that point that
is the genuinely useful next step.

---

## References

These are the sources behind the exercise designs. They are provided so you can
read the underlying work yourself. Again: none of them studied Amblyo.

**Binocular and dichoptic methods**

- Kelly KR et al. (2016). Binocular iPad game vs patching for treatment of
  amblyopia in children. *JAMA Ophthalmology*. Randomised clinical trial.
- Holmes JM et al. (2016). Effect of a binocular iPad game vs part-time patching
  in children aged 5 to 12 years with amblyopia. *JAMA Ophthalmology*.
  Randomised clinical trial.
- Xiao S et al. (2022). Randomised controlled trial of a dichoptic digital
  therapeutic for amblyopia. *Ophthalmology*.
- Li SL et al. (2022). Randomised clinical trial of streaming contrast-rebalanced
  binocular movies versus patching in children aged 3 to 7. *Journal of AAPOS*.
- Manh VM et al. (2018). A randomised trial of a binocular iPad game versus
  part-time patching in children aged 13 to 16. *American Journal of
  Ophthalmology*.

**Perceptual learning**

- Polat U et al. (2004). Improving vision in adult amblyopia by perceptual
  learning. *Proceedings of the National Academy of Sciences*.
- Levi DM, Li RW (2009). Perceptual learning as a potential treatment for
  amblyopia: a mini-review. *Vision Research*.
- Tsirlin I, Colpa L, Goltz HC, Wong AMF (2015). Behavioural training as new
  treatment for adult amblyopia: a meta-analysis. *Investigative Ophthalmology &
  Visual Science*.

**Method**

- Levitt H (1971). Transformed up-down methods in psychoacoustics. *Journal of
  the Acoustical Society of America*.

---

## Questions worth asking your eye doctor

If you want to bring Amblyo up at an appointment, these are useful questions:

- Is my correction up to date, and am I wearing it enough?
- Is binocular or dichoptic work appropriate for me, or should I be patching?
- How much daily practice would you recommend, and for how long?
- What would you expect to see change, and by when?
- Is there anything about my eyes that means I should not be doing this?

You can export your practice history from Progress and show it to them.
<!-- claims-lint:enable -->
