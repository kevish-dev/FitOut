# Built-in exercise library

The library contains 144 system exercises: common free-weight, cable, machine, bodyweight, core, cardio and mobility movements. It is shared by the exercise browser, routine builder, exercise replacement and live workout picker. Custom exercises remain available for movements outside the catalogue.

Search covers names, aliases, equipment, movement patterns and primary/secondary muscles. Multiple search words may appear in any order. Equipment, type, muscle and favorite filters combine. Muscle filters include secondary muscles. Multi-select keeps the order in which the user selected exercises, including selections hidden by a later filter.

Exercises have appropriate weight/repetition, repetition-only or time/distance tracking. Band and assisted movements use repetition-only tracking rather than contributing an invented load to weighted volume. The catalogue does not prescribe a personalized routine.

## Bundled exercise images

21 original illustrations supplied in `Imgs/` are bundled in the asset catalogue. [EXERCISE_ARTWORK.json](EXERCISE_ARTWORK.json) records each source filename, assigned exercise, dimensions and SHA-256 hash. Originals are copied without cropping, recoloring or resizing. They are available offline.

| Group | Illustrated exercises |
| --- | --- |
| Chest | Machine chest press, incline machine chest press, pec deck fly |
| Triceps | Cable bar pushdown, rope pushdown, dumbbell overhead extension |
| Legs | Barbell squat, leg press, leg extension |
| Core | Crunch, dragon flag, weighted Russian twist |
| Back | Lat pulldown, seated cable row, face pull |
| Shoulders | Arnold press, seated dumbbell shoulder press, lateral raise |
| Biceps | EZ-bar curl, incline dumbbell curl, hammer curl |

Assignments follow the movement shown rather than the filename alone: the “Leg Extension and Curl” file shows leg extensions, and the “Triceps Pushdown Machine” file shows a cable rope pushdown. Machine press artwork is not assigned to barbell/dumbbell presses. Incline machine press, rope pushdown and dragon flag were added as selectable exercises; existing IDs remain unchanged. Russian twist supports a dumbbell or plate, matching its illustration.

Images appear in library/search results, add/replace exercise pickers, routine cards, live workout headers and workout summaries. Exercise details and expanded routine cards offer an image preview; live workout and summary thumbnails also open it. The full-screen viewer fits the entire illustration and supports pinch zoom, panning, double-tap zoom/reset and VoiceOver zoom actions. Rotation refits the image. Static picker thumbnails do not intercept exercise selection.

## Adding more system images

Each built-in exercise has a permanent image asset key. [EXERCISE_IMAGES.csv](EXERCISE_IMAGES.csv) lists all 144 exercise IDs, names, asset keys and suggested filenames. Photos showing posture and illustrations showing muscles both work; use an image that depicts the exact listed exercise and equipment.

For example, the existing bench press has ID `bench`, asset key `exercise-bench`, and suggested filename `exercise-bench.png`. Add the supplied image to an image set named `exercise-bench` inside `FitOut/Resources/Assets.xcassets`. Its `Contents.json` can be:

```json
{
  "images": [{ "filename": "exercise-bench.png", "idiom": "universal" }],
  "info": { "author": "xcode", "version": 1 }
}
```

Use PNG or JPEG artwork with enough resolution to inspect the posture. Include the whole diagram with breathing room around it. Artwork is fitted without cropping in thumbnails and the larger exercise detail view. No network download or end-user image upload is involved.

Until a matching image is bundled, rows show a neutral category symbol. Exercise detail explicitly says the image is coming soon. These symbols are placeholders, not exercise demonstrations. Custom/unknown exercise IDs do not borrow a built-in image.

## Compatibility

The original 13 exercise IDs and tracking types are unchanged. Existing routines, templates and workout snapshots continue to refer to the same exercises. On store initialization, missing built-in entries are added and system metadata is refreshed while preserving favorites and custom records. Reopening does not duplicate exercises. Images and categories are resolved from catalogue metadata; no persistence schema migration is needed.

`ExerciseCatalogueTests` covers unique entries and image keys, bundled-image resolution, legacy/template references, search/filter behavior, tracking types and upgrades from an existing library. Tests are compiled but app/simulator execution is intentionally left to the project owner.
