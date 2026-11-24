using UnityEngine;

namespace Damar
{
    /// <summary>
    /// تحكم اللص سيراً على الأقدام + ركوب/نزول السيارات.
    /// يحتاج CharacterController. ضع نموذج الشخصية (من Mixamo مثلاً) ابناً له واربطه في visual.
    /// Animator: معامل float اسمه Speed ومعامل bool اسمه Robbing.
    /// </summary>
    [RequireComponent(typeof(CharacterController))]
    public class PlayerController : MonoBehaviour
    {
        [Header("الحركة")]
        public float walkSpeed = 4.6f;
        public float sprintSpeed = 8.2f;
        public float gravity = -20f;
        public float turnSpeed = 12f;
        [Tooltip("ثوانٍ من الركض حتى تنفد اللياقة")] public float sprintDuration = 7f;
        [Tooltip("ثوانٍ لاستعادة اللياقة كاملة")] public float staminaRecovery = 5f;

        [Header("مراجع")]
        public Transform cameraTransform;
        public GameObject visual;
        public Animator animator;

        [Header("السيارات")]
        public float enterRadius = 3.5f;
        public LayerMask vehicleMask = ~0;
        [Tooltip("أقصى سرعة (كم/س) يُسمح عندها بالنزول")] public float maxExitSpeedKmh = 25f;

        public float Stamina { get; private set; } = 1f;
        public bool IsRobbing { get; set; }
        public VehicleController CurrentVehicle { get; private set; }
        public Vector3 Position => CurrentVehicle ? CurrentVehicle.transform.position : transform.position;
        public Vector3 Velocity => CurrentVehicle ? CurrentVehicle.Rb.GetVelocity() : velocity;
        public bool OnFoot => CurrentVehicle == null;

        static readonly int SpeedHash = Animator.StringToHash("Speed");
        static readonly int RobbingHash = Animator.StringToHash("Robbing");

        CharacterController cc;
        Vector3 velocity;
        float verticalSpeed;
        readonly Collider[] hits = new Collider[16];

        void Awake()
        {
            cc = GetComponent<CharacterController>();
            if (cameraTransform == null && Camera.main != null) cameraTransform = Camera.main.transform;
        }

        void Update()
        {
            if (CurrentVehicle != null)
            {
                if (Input.GetKeyDown(KeyCode.F)) TryExitVehicle();
                return;
            }

            float dt = Time.deltaTime;
            Vector3 camF = cameraTransform ? cameraTransform.forward.Flat().normalized : Vector3.forward;
            Vector3 camR = cameraTransform ? cameraTransform.right.Flat().normalized : Vector3.right;
            Vector2 input = new Vector2(Input.GetAxisRaw("Horizontal"), Input.GetAxisRaw("Vertical"));
            Vector3 move = Vector3.ClampMagnitude(camF * input.y + camR * input.x, 1f);

            bool sprint = Input.GetKey(KeyCode.LeftShift) && move.sqrMagnitude > 0.01f && Stamina > 0.03f;
            Stamina = Mathf.Clamp01(Stamina + (sprint ? -dt / sprintDuration : dt / staminaRecovery));
            float speed = sprint ? sprintSpeed : walkSpeed;
            if (IsRobbing) move = Vector3.zero;

            velocity = Vector3.Lerp(velocity, move * speed, 1f - Mathf.Exp(-10f * dt));
            verticalSpeed = cc.isGrounded ? -2f : verticalSpeed + gravity * dt;
            cc.Move((velocity + Vector3.up * verticalSpeed) * dt);

            if (velocity.sqrMagnitude > 0.09f)
            {
                Quaternion look = Quaternion.LookRotation(velocity.Flat());
                transform.rotation = Quaternion.Slerp(transform.rotation, look, 1f - Mathf.Exp(-turnSpeed * dt));
            }

            if (animator)
            {
                animator.SetFloat(SpeedHash, velocity.Flat().magnitude, 0.1f, dt);
                animator.SetBool(RobbingHash, IsRobbing);
            }

            if (Input.GetKeyDown(KeyCode.F)) TryEnterNearestVehicle();
        }

        public VehicleController FindNearestVehicle()
        {
            int n = Physics.OverlapSphereNonAlloc(transform.position, enterRadius, hits, vehicleMask, QueryTriggerInteraction.Ignore);
            VehicleController best = null;
            float bestD = float.MaxValue;
            for (int i = 0; i < n; i++)
            {
                var v = hits[i].GetComponentInParent<VehicleController>();
                if (v == null || v.IsOccupied) continue;
                float d = (v.transform.position - transform.position).sqrMagnitude;
                if (d < bestD) { bestD = d; best = v; }
            }
            return best;
        }

        void TryEnterNearestVehicle()
        {
            var v = FindNearestVehicle();
            if (v != null) EnterVehicle(v);
        }

        public void EnterVehicle(VehicleController v)
        {
            if (v.isPolice) WantedSystem.I.Add(2);
            else if (v.GetComponent<TrafficAI>() != null && PoliceSpawner.I != null && PoliceSpawner.I.AnyPoliceSees(transform.position))
                WantedSystem.I.Add(1);

            IsRobbing = false;
            CurrentVehicle = v;
            v.SetPlayerDriver(true);
            cc.enabled = false;
            if (visual) visual.SetActive(false);
            transform.SetParent(v.transform, false);
            transform.localPosition = Vector3.zero;
            transform.localRotation = Quaternion.identity;
        }

        void TryExitVehicle()
        {
            if (CurrentVehicle.SpeedKmh > maxExitSpeedKmh) return;
            ExitVehicle();
        }

        void ExitVehicle()
        {
            var v = CurrentVehicle;
            v.SetPlayerDriver(false);
            CurrentVehicle = null;
            transform.SetParent(null, true);
            Vector3 exitPos = v.transform.position - v.transform.right * 2f + Vector3.up * 0.3f;
            transform.SetPositionAndRotation(exitPos, Quaternion.LookRotation(v.transform.forward.Flat()));
            cc.enabled = true;
            if (visual) visual.SetActive(true);
            velocity = Vector3.zero;
        }

        public void Teleport(Vector3 position, Quaternion rotation)
        {
            if (CurrentVehicle != null) ExitVehicle();
            cc.enabled = false;
            transform.SetPositionAndRotation(position, rotation);
            cc.enabled = true;
            velocity = Vector3.zero;
            IsRobbing = false;
        }
    }
}
