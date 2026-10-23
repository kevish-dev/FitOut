# Built-in exercise library

The library contains 141 system exercises: common free-weight, cable, machine, bodyweight, core, cardio and mobility movements. It is shared by the exercise browser, routine builder, exercise replacement and live workout picker. Custom exercises remain available for movements outside the catalogue.

Search covers names, aliases, equipment, movement patterns and primary/secondary muscles. Multiple search words may appear in any order. Equipment, type, muscle and favorite filters combine. Muscle filters include secondary muscles. Multi-select keeps the order in which the user selected exercises, including selections hidden by a later filter.

Exercises have appropriate weight/repetition, repetition-only or time/distance tracking. Band and assisted movements use repetition-only tracking rather than contributing an invented load to weighted volume. The catalogue does not prescribe a personalized routine.

## System images to supply

No exercise pictures have been supplied yet. Each built-in exercise already has a permanent image asset key. [EXERCISE_IMAGES.csv](EXERCISE_IMAGES.csv) lists all 141 exercise IDs, names, asset keys and suggested filenames. Photos showing posture and illustrations showing muscles both work; use an image that depicts the exact listed exercise and equipment.

For example, the existing bench press has ID `bench`, asset key `exercise-bench`, and suggested filename `exercise-bench.png`. Add the supplied image to an image set named `exercise-bench` inside `FitOut/Resources/Assets.xcassets`. Its `Contents.json` can be:

```json
{
  "images": [{ "filename": "exercise-bench.png", "idiom": "universal" }],
  "info": { "author": "xcode", "version": 1 }
}
```

Use PNG or JPEG artwork, ideally at least 800 px on its shortest side. Include the whole posture/diagram with breathing room around it. Artwork is fitted without cropping in thumbnails and the larger exercise detail view. The same asset is used in routine cards, live workouts and workout summaries. No network download or end-user image upload is involved.

Until a matching image is bundled, rows show a neutral category symbol. Exercise detail explicitly says the image is coming soon. These symbols are placeholders, not exercise demonstrations. Custom/unknown exercise IDs do not borrow a built-in image.

## Compatibility

The original 13 exercise IDs and tracking types are unchanged. Existing routines, templates and workout snapshots continue to refer to the same exercises. On store initialization, missing built-in entries are added and system metadata is refreshed while preserving favorites and custom records. Reopening does not duplicate exercises. Images and categories are resolved from catalogue metadata; no persistence schema migration is needed.

`ExerciseCatalogueTests` covers unique entries and image keys, legacy/template references, search/filter behavior, tracking types and upgrades from an existing library. Tests were added for device/Xcode execution; app/simulator execution is intentionally left to the project owner.
