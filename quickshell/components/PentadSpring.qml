import QtQml
import qs.theme
import "../logic/spring.mjs" as SpringLogic

// One damped spring, "stiffness damping" like the motion tokens. The owner steps it from its
// FrameAnimation with advance(frameTime) and binds visuals to `value`. `value` and `velocity`
// are the spring's own state: set them only through jump()/kick(), never bind them.
// With reduced motion every change of `target` lands at once.
QtObject {
    id: root
    property real stiffness: 400
    property real damping: 30
    property real target: 0
    property real value: 0
    property real velocity: 0
    readonly property bool reduced: Theme.tokens.reducedMotion
    readonly property bool settled: SpringLogic.springSettled(value, velocity, target)

    onTargetChanged: if (reduced) snap()
    onReducedChanged: if (reduced) snap()

    function advance(dt) {
        if (reduced || settled) {
            snap();
            return;
        }
        const next = SpringLogic.stepSpring(value, velocity, target, stiffness, damping, dt);
        value = next.value;
        velocity = next.velocity;
    }
    function snap() {
        value = target;
        velocity = 0;
    }
    // Moves the value without touching the target, so the spring swings back from there.
    function kick(position) {
        if (!reduced) value = position;
    }
    // Adds a velocity, so the spring swings out from where it is; ignored with reduced motion.
    function push(extraVelocity) {
        if (!reduced) velocity += extraVelocity;
    }
    // Starts again from a position at rest; with reduced motion it stays on the target.
    function jump(position) {
        velocity = 0;
        value = reduced ? target : position;
    }
}
