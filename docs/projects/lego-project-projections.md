# Lego Project Projections

## Assumptions

- Start date: April 27, 2026.
- One team is working sequentially with light overlap between phases.
- The first release targets practical accuracy, not perfect exact-piece recall.
- Existing OneDrive access and image export are available.

## Timeline Projection

| Phase | Focus | Estimated Duration | Projected Window |
| --- | --- | --- | --- |
| 1 | Intake contract and labeled dataset | 2 to 3 weeks | Apr 27, 2026 to May 15, 2026 |
| 2 | Lego presence detection | 2 to 4 weeks | May 11, 2026 to Jun 12, 2026 |
| 3 | Exact piece identification | 2 to 3 weeks | Jun 8, 2026 to Jul 3, 2026 |
| 4 | Partial occlusion handling | 2 to 5 weeks | Jun 22, 2026 to Aug 7, 2026 |
| 5 | Review workflow and quality metrics | 1 to 2 weeks | Aug 3, 2026 to Aug 21, 2026 |

## Delivery Ranges

### Optimistic

- First working version: June 2026
- Review-ready version with ranked candidates: July 2026
- Practical version for obstructed pieces: early August 2026

### Expected

- First working version: mid-June to early July 2026
- Review-ready version with ranked candidates: July 2026
- Practical version for obstructed pieces: August 2026

### Conservative

- First working version: July 2026
- Review-ready version with ranked candidates: August 2026
- Practical version for obstructed pieces: September 2026

## Milestone Forecast

### Milestone 1: Ingestion Baseline

- Outcome: OneDrive images are discovered, copied, deduplicated, and tracked.
- Target: Mid-May 2026.

### Milestone 2: Presence Detection Operational

- Outcome: The system can decide whether an image likely contains Lego.
- Target: Early to mid-June 2026.

### Milestone 3: Piece Candidate Matching

- Outcome: Positive images return the most likely piece candidates with confidence scores.
- Target: Late June to early July 2026.

### Milestone 4: Occlusion-Aware Classification

- Outcome: The system remains usable when pieces are partially hidden, cropped, or blocked.
- Target: July to early August 2026.

### Milestone 5: Review and Metrics

- Outcome: Low-confidence predictions route to review and quality metrics are measurable across new batches.
- Target: August 2026.

## Projection Risks

- The biggest schedule driver is the quality of labeled images for partially visible pieces.
- Exact-piece identification may need retrieval or top-k ranking instead of single-label classification.
- If many images contain mixed bins or multiple pieces, annotation effort can expand quickly.
- A weak negative dataset will slow down the presence-detector threshold tuning.

## Recommended Target

Plan for an expected delivery window ending in August 2026, with a first usable checkpoint in June 2026 and a fallback buffer into September 2026 if the occlusion problem proves harder than expected.