# Share Extension UI State Map

## Deterministic States

- `extracting`: gather transcript/PDF text/source details.
- `fetching`: fetch page metadata/content.
- `analyzing`: AI or fallback organization stage.
- `saving`: persist pattern and assets to backend.
- `success`: save complete, positive confirmation, auto-close.

## Failure Routing

- Recoverable error -> editable fallback path
  - Overlay hides.
  - User remains in editor with title/tags fallback.
  - Supportive notice explains that basic details were saved and can be edited.
- Terminal error -> explicit safe exits
  - Clear explanation in alert.
  - `Try Again` (re-attempt step) or `Close` (safe dismiss).

## Fallback Notes

- AI unavailable/limited/disabled: proceed with OG/basic extraction and editable notice.
- No extractable PDF text: seed title fallback and allow manual save.
- Video transcript unavailable: keep link flow editable instead of dead-end dismissal.
