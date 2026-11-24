using UnityEngine;

namespace Damar
{
    /// <summary>
    /// منطق قيادة مشترك للذكاء الاصطناعي: التوجه نحو نقطة، تخفيف السرعة في المنعطفات،
    /// والرجوع للخلف تلقائياً عند العلوق.
    /// </summary>
    public class DriveHelper
    {
        float stuckTime;
        float reverseTime;

        public void DriveTowards(VehicleController v, Vector3 target, float maxKmh, float dt)
        {
            Vector3 to = (target - v.transform.position).Flat();
            float angle = Vector3.SignedAngle(v.transform.forward.Flat(), to, Vector3.up); // + = يمين

            if (reverseTime > 0f)
            {
                reverseTime -= dt;
                v.Throttle = -1f;
                v.Steer = -Mathf.Sign(angle);
                v.Handbrake = false;
                return;
            }

            float desired = maxKmh * (1f - Mathf.Min(Mathf.Abs(angle) / 90f, 1f) * 0.7f);
            float speed = v.ForwardSpeed * 3.6f;
            v.Throttle = speed < desired ? 1f : (speed > desired + 7f ? -0.7f : 0f);
            v.Steer = Mathf.Clamp(angle / 25f, -1f, 1f);
            v.Handbrake = false;

            if (v.Throttle > 0.5f && v.SpeedKmh < 3.5f) stuckTime += dt;
            else stuckTime = Mathf.Max(0f, stuckTime - dt);
            if (stuckTime > 1.3f) { reverseTime = 1.1f; stuckTime = 0f; }
        }

        public static void Stop(VehicleController v)
        {
            v.Throttle = v.ForwardSpeed > 0.5f ? -1f : 0f;
            v.Steer = 0f;
            v.Handbrake = v.SpeedKmh < 2f;
        }
    }
}
