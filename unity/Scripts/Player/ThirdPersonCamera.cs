using UnityEngine;

namespace Damar
{
    /// <summary>
    /// كاميرا الشخص الثالث: تدور بالفأرة، تبتعد مع السرعة في السيارة،
    /// تعود خلف السيارة تلقائياً، ولا تخترق الجدران.
    /// ضعها على Main Camera.
    /// </summary>
    public class ThirdPersonCamera : MonoBehaviour
    {
        public PlayerController player;

        [Header("المسافات")]
        public float footDistance = 5.2f;
        public float footHeight = 1.65f;
        public float carDistance = 9.5f;
        public float carHeight = 1.5f;

        [Header("الفأرة")]
        public float sensitivity = 2.2f;
        public float minPitch = -5f, maxPitch = 65f;
        [Tooltip("ثوانٍ بعد آخر حركة للفأرة قبل أن تعود الكاميرا خلف السيارة")]
        public float autoAlignDelay = 1f;

        [Header("التصادم")]
        public LayerMask obstacleMask = ~0;
        public float collisionRadius = 0.3f;

        [Header("مجال الرؤية")]
        public float baseFov = 62f;
        public float maxExtraFov = 16f;

        float yaw, pitch = 17f;
        float lastMouseTime = -10f;
        float shake;
        Camera cam;

        void Awake()
        {
            cam = GetComponent<Camera>();
            Cursor.lockState = CursorLockMode.Locked;
            Cursor.visible = false;
        }

        public void Shake(float amount) => shake = Mathf.Max(shake, Mathf.Clamp01(amount));

        void LateUpdate()
        {
            if (player == null) return;
            float dt = Time.deltaTime;

            float mx = Input.GetAxis("Mouse X"), my = Input.GetAxis("Mouse Y");
            if (Mathf.Abs(mx) + Mathf.Abs(my) > 0.001f) lastMouseTime = Time.time;
            yaw += mx * sensitivity;
            pitch = Mathf.Clamp(pitch - my * sensitivity, minPitch, maxPitch);

            var vehicle = player.CurrentVehicle;
            float speed = vehicle ? vehicle.SpeedKmh / 3.6f : 0f;
            if (vehicle && Time.time - lastMouseTime > autoAlignDelay)
            {
                float targetYaw = vehicle.transform.eulerAngles.y;
                yaw = Mathf.LerpAngle(yaw, targetYaw, 1f - Mathf.Exp(-2.6f * dt));
                pitch = Mathf.Lerp(pitch, 15f, 1f - Mathf.Exp(-1.5f * dt));
            }

            Vector3 target = player.Position + Vector3.up * (vehicle ? carHeight : footHeight);
            float dist = vehicle ? carDistance + speed * 0.07f : footDistance;
            Quaternion rot = Quaternion.Euler(pitch, yaw, 0f);
            Vector3 desired = target - rot * Vector3.forward * dist;

            // منع اختراق المباني
            Vector3 dir = desired - target;
            if (Physics.SphereCast(target, collisionRadius, dir.normalized, out RaycastHit hit, dir.magnitude, obstacleMask, QueryTriggerInteraction.Ignore)
                && (vehicle == null || hit.transform.root != vehicle.transform.root))
            {
                desired = target + dir.normalized * Mathf.Max(0.5f, hit.distance - 0.1f);
            }

            if (shake > 0f)
            {
                desired += Random.insideUnitSphere * shake * 0.4f;
                shake = Mathf.Max(0f, shake - dt * 2.5f);
            }

            float follow = vehicle ? 9f : 16f;
            transform.position = Vector3.Lerp(transform.position, desired, 1f - Mathf.Exp(-follow * dt));
            transform.rotation = Quaternion.LookRotation(target + Vector3.up * (vehicle ? 0.7f : 0.15f) - transform.position);

            if (cam)
            {
                float fov = baseFov + Mathf.Min(speed, 35f) / 35f * maxExtraFov;
                cam.fieldOfView = Mathf.Lerp(cam.fieldOfView, fov, 1f - Mathf.Exp(-3f * dt));
            }
        }
    }
}
