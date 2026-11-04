# Funkin' Revival: scripting and character JSON additions

## Character JSON: `healthIcon`

All of these fields are optional.

| Field | Type | Default | What it does |
| --- | --- | --- | --- |
| `color` | string | the main color of the icon's image | Color of this character's side of the health bar, such as `"#31B0D1"`. |
| `winningThreshold` | number | `0.8` | Health, as a fraction of the maximum, above which the icon shows its winning state. |
| `losingThreshold` | number | `0.2` | Health, as a fraction of the maximum, below which the icon shows its losing state. |
| `bopScale` | number | `0.2` | How much the icon grows when it bops on the beat. |

```json
"healthIcon": {
  "id": "bf",
  "color": "#31B0D1",
  "losingThreshold": 0.3,
  "bopScale": 0.35
}
```

When `color` is missing, the health bar uses the most prominent color of the health icon.
If both characters end up with similar colors, the opponent's side is adjusted so the bar stays readable.

## HScript

### Health bar

Available on `PlayState.instance`:

- `setHealthBarColors(opponent, player)`: sets both colors at once.
- `tweenHealthBarColors(opponent, player, duration)`: fades to the new colors.
- `resetHealthBarColors()`: goes back to the colors of the health icons.
- `healthBarOpponentColor` and `healthBarPlayerColor`: the colors in use (read only).

The health icons also have `getBarColor()`, `barColorOverride`, `winningThreshold`, `losingThreshold` and `bopScale`.

### `ScriptUtil`

`ScriptUtil` is imported in every script, like `Paths` and `Preferences`.
Wherever a color is expected, scripts can pass an `Int` (`0xFF31B0D1`) or a `String` (`"#31B0D1"`, `"0xFF31B0D1"`, `"red"`).

```haxe
// Colors
ScriptUtil.color("#31B0D1");
ScriptUtil.lerpColor("red", "blue", 0.5);
ScriptUtil.darken("#31B0D1", 0.3);
ScriptUtil.lighten("#31B0D1", 0.3);
ScriptUtil.withAlpha("#31B0D1", 0.5);

// Tweens, with the name of an ease from FlxEase
ScriptUtil.tween(sprite, {x: 100, alpha: 0.5}, 1.0, "quadOut", function() trace("done"));

// Health bar
ScriptUtil.setHealthBarColors("#FF0000", "#00FF00");
ScriptUtil.setHealthBarColors("#FF0000", "#00FF00", 0.5); // fades over half a second
ScriptUtil.resetHealthBarColors();

// Math
ScriptUtil.clamp(value, 0, 1);
ScriptUtil.lerp(a, b, 0.5);
ScriptUtil.randomFloat(0, 1);
ScriptUtil.randomInt(1, 6);
```

## Animation Editor

The side panel of the Animation Editor is `assets-revival/preload/data/ui/animation-editor/revival-editor-panel.xml`.
The `assets-revival` folder is part of this repository and is included in the build next to `assets`.
