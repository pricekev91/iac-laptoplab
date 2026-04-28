# Lego Project Charter

## Summary

Build a workflow that pulls photos from OneDrive, determines whether each image contains Lego, and then attempts to identify the exact Lego piece when confidence is high enough.

## Goals

- Detect whether Lego is present in each image before spending compute on detailed classification.
- Return the most likely exact Lego piece or a ranked candidate list when full certainty is not possible.
- Preserve a review path for low-confidence images and partially obscured pieces.

## Scope

- Ingest photos from OneDrive.
- Run first-stage Lego presence detection.
- Run second-stage piece identification for positive images.
- Store confidence, ranked candidates, and review status.

## Constraints

- Many photos will not contain Lego at all.
- Some Lego pieces will be partially hidden or cropped.
- Lighting, shadows, background clutter, and motion blur will reduce classification quality.
- Exact-piece identification will be harder than presence detection and will require a fallback review workflow.

## Success Criteria

- Non-Lego images are filtered reliably enough to reduce wasted downstream processing.
- Positive images return either a high-confidence piece prediction or a ranked shortlist.
- Low-confidence and occluded cases are routed to human review instead of silently accepted.
- The workflow can be rerun on new OneDrive batches without changing the contract.

## Risks

- Insufficient labeled examples for rare or partially visible pieces.
- Ambiguity between visually similar Lego parts.
- OneDrive image quality and metadata inconsistency.
- Overfitting to a narrow set of image backgrounds or camera angles.