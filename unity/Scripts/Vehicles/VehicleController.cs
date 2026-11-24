using UnityEngine;

namespace Damar
{
    /// <summary>
    /// سيارة بفيزياء WheelCollider. يقودها اللاعب أو الذكاء الاصطناعي عبر Throttle/Steer/Handbrake.
    /// الإعداد: Rigidbody (الكتلة ~1400)، 4 WheelColliders، ونماذج العجلات في wheels[].mesh.
    /// </summary>
    [RequireComponent(typeof(Rigidbody))]
    public class VehicleController : MonoBehaviour
    {
        [System.Serializable]
        public class Wheel
        {
            public WheelCollider collider;
            public Transform mesh;
            public bool steer;
            public bool motor;
        }

        public Wheel[] wheels = new Wheel[4];

        [Header("المحرك")]
        public float motorTorque = 1800f;
        public float brakeTorque = 4000f;
        public float handbrakeTorque = 7000f;
        public float maxSpeedKmh = 160f;
        public float maxSteerAngle = 32f;
        public float downforce = 40f;
        public Vector3 centerOfMass = new Vector3(0f, -0.45f, 0.1f);

        [Header("النوع")]
        public bool isPolice;

        [Header("الإضاءة الخلفية (اختياري)")]
        public Renderer brakeLightRenderer;
        public string emissionProperty = "_EmissiveColor"; // HDRP: _EmissiveColor | URP/Built-in: _EmissionColor
        public Color brakeOn = new Color(8f, 0.2f, 0.2f), brakeOff = new Color(1f, 0.05f, 0.05f);

        [Header("مدخلات (يكتبها اللاعب أو الذكاء الاصطناعي)")]
        [Range(-1, 1)] public float Throttle;
        [Range(-1, 1)] public float Steer;
        public bool Handbrake;

        public Rigidbody Rb { get; private set; }
        public bool PlayerDriving { get; private set; }
        public bool IsOccupied => PlayerDriving;
        public float SpeedKmh => Rb.GetVelocity().magnitude * 3.6f;
        public float ForwardSpeed => Vector3.Dot(Rb.GetVelocity(), transform.forward);
        public bool IsBraking { get; private set; }

        /// <summary>يُطلق عند الاصطدام بقوة (للصوت واهتزاز الكاميرا).</summary>
        public event System.Action<float, Collision> Crashed;

        MaterialPropertyBlock mpb;

        void Awake()
        {
            Rb = GetComponent<Rigidbody>();
            Rb.centerOfMass = centerOfMass;
            mpb = new MaterialPropertyBlock();
        }

        public void SetPlayerDriver(bool driving)
        {
            PlayerDriving = driving;
            foreach (var ai in GetComponents<IVehicleAI>()) ai.SetEnabled(!driving);
            if (!driving) { Throttle = 0f; Steer = 0f; Handbrake = true; }
            else Handbrake = false;
        }

        void Update()
        {
            if (PlayerDriving)
            {
                Throttle = Input.GetAxis("Vertical");
                Steer = Input.GetAxis("Horizontal");
                Handbrake = Input.GetKey(KeyCode.Space);
            }

            if (brakeLightRenderer)
            {
                brakeLightRenderer.GetPropertyBlock(mpb);
                mpb.SetColor(emissionProperty, IsBraking || Handbrake ? brakeOn : brakeOff);
                brakeLightRenderer.SetPropertyBlock(mpb);
            }
        }

        void FixedUpdate()
        {
            float fwd = ForwardSpeed;
            float speedFactor = Mathf.InverseLerp(0f, maxSpeedKmh / 3.6f, Mathf.Abs(fwd));
            float steerAngle = Steer * maxSteerAngle * Mathf.Lerp(1f, 0.35f, speedFactor);

            // الضغط عكس اتجاه الحركة = فرامل، وإلا = تسارع/رجوع
            IsBraking = (Throttle < -0.05f && fwd > 1f) || (Throttle > 0.05f && fwd < -1f);
            bool overSpeed = SpeedKmh > maxSpeedKmh;

            foreach (var w in wheels)
            {
                if (w == null || w.collider == null) continue;
                if (w.steer) w.collider.steerAngle = steerAngle;
                if (w.motor) w.collider.motorTorque = IsBraking || overSpeed ? 0f : Throttle * motorTorque;

                float brake = IsBraking ? brakeTorque * Mathf.Abs(Throttle) : 0f;
                if (Mathf.Abs(Throttle) < 0.05f) brake = 60f; // مقاومة التدحرج
                if (Handbrake && !w.steer) brake = handbrakeTorque;
                w.collider.brakeTorque = brake;

                if (w.mesh)
                {
                    w.collider.GetWorldPose(out Vector3 pos, out Quaternion rot);
                    w.mesh.SetPositionAndRotation(pos, rot);
                }
            }

            Rb.AddForce(-transform.up * Rb.GetVelocity().magnitude * downforce);
        }

        void OnCollisionEnter(Collision c)
        {
            float impact = c.relativeVelocity.magnitude;
            if (impact < 5f) return;
            Crashed?.Invoke(impact, c);

            // صدم سيارة شرطة بقوة يرفع النجوم
            if (PlayerDriving && impact > 9f)
            {
                var other = c.collider.GetComponentInParent<VehicleController>();
                if (other != null && other.isPolice) WantedSystem.I.Add(1);
            }
        }
    }

    /// <summary>أي ذكاء اصطناعي يقود سيارة يجب أن يتوقف عندما يركبها اللاعب.</summary>
    public interface IVehicleAI
    {
        void SetEnabled(bool enabled);
    }
}
