using UnityEngine;
using UnityEngine.AI;

namespace Damar
{
    /// <summary>
    /// سيارة شرطة تطارد اللاعب:
    /// - إن رأته مباشرة تتجه إليه وتتوقع حركته
    /// - وإلا تتبع مساراً على شبكة الطرق (NavMesh بمنطقة اسمها Road)
    /// - إن كان اللاعب ماشياً تتوقف قربه وينزل شرطي يلاحقه
    /// </summary>
    [RequireComponent(typeof(VehicleController))]
    public class PoliceCarAI : MonoBehaviour, IVehicleAI
    {
        [Header("المطاردة")]
        public float sightRange = 65f;
        public float directChaseRange = 45f;
        public float baseMaxKmh = 100f;
        public float extraKmhPerStar = 7f;
        [Tooltip("الطبقات التي تحجب الرؤية (المباني)")]
        public LayerMask sightBlockers;
        public string roadAreaName = "Road";

        [Header("الشرطي الراجل")]
        public PoliceOfficerAI officerPrefab;
        public Transform officerExitPoint;
        public float officerExitRange = 30f;

        public bool Chasing => enabled && WantedSystem.I != null && WantedSystem.I.Level > 0;
        public PoliceOfficerAI Officer { get; private set; }

        VehicleController v;
        PlayerController player;
        readonly DriveHelper drive = new DriveHelper();
        NavMeshPath path;
        int corner;
        float repathTimer, officerCooldown;
        int roadMask;

        void Awake()
        {
            v = GetComponent<VehicleController>();
            v.isPolice = true;
            path = new NavMeshPath();
            int area = NavMesh.GetAreaFromName(roadAreaName);
            roadMask = area >= 0 ? 1 << area : NavMesh.AllAreas;
        }

        void Start() { player = GameManager.I.player; }

        public void SetEnabled(bool enabled)
        {
            this.enabled = enabled;
            if (!enabled && Officer) Officer.ReturnToCar();
        }

        public bool CanSee(Vector3 pos)
        {
            Vector3 eye = transform.position + Vector3.up * 1.5f;
            return (pos - eye).sqrMagnitude < sightRange * sightRange
                && !Physics.Linecast(eye, pos + Vector3.up * 1.2f, sightBlockers, QueryTriggerInteraction.Ignore);
        }

        void Update()
        {
            float dt = Time.deltaTime;
            officerCooldown -= dt;
            if (!Chasing) { DriveHelper.Stop(v); return; }

            Vector3 target = player.Position;
            float d = (target - transform.position).Flat().magnitude;
            bool sees = CanSee(target);
            if (sees) WantedSystem.I.ReportSeen();

            if (Officer != null) { DriveHelper.Stop(v); return; }

            Vector3 aim;
            if (sees && d < directChaseRange)
            {
                aim = target + player.Velocity * Mathf.Clamp(d / 25f, 0f, 1.2f);
            }
            else
            {
                repathTimer -= dt;
                if (repathTimer <= 0f) Repath(target);
                aim = NextCorner();
            }

            float maxKmh = baseMaxKmh + extraKmhPerStar * WantedSystem.I.Level;
            if (player.OnFoot && d < officerExitRange) maxKmh = Mathf.Clamp((d - 6f) * 4f, 0f, maxKmh);
            drive.DriveTowards(v, aim, maxKmh, dt);
            if (player.OnFoot && d < 9f) DriveHelper.Stop(v);

            // ضغط الاعتقال
            bool playerSlow = player.OnFoot || player.CurrentVehicle.SpeedKmh < 10f;
            if (d < 7f && v.SpeedKmh < 10f && playerSlow)
                GameManager.I.AddArrestPressure(player.OnFoot ? 0.25f : 0.35f);

            // نزول الشرطي
            if (player.OnFoot && d < officerExitRange && v.SpeedKmh < 10f && officerCooldown <= 0f && officerPrefab)
            {
                Transform exit = officerExitPoint ? officerExitPoint : transform;
                Officer = Instantiate(officerPrefab, exit.position - transform.right * 1.8f, transform.rotation);
                Officer.Init(this);
            }
        }

        void Repath(Vector3 target)
        {
            repathTimer = 0.5f;
            corner = 1;
            if (NavMesh.SamplePosition(target, out NavMeshHit hit, 40f, roadMask))
                NavMesh.CalculatePath(transform.position, hit.position, roadMask, path);
        }

        Vector3 NextCorner()
        {
            if (path.corners == null || path.corners.Length < 2) return player.Position;
            while (corner < path.corners.Length - 1 && (path.corners[corner] - transform.position).Flat().magnitude < 7f) corner++;
            return path.corners[Mathf.Min(corner, path.corners.Length - 1)];
        }

        public void OnOfficerReturned()
        {
            Officer = null;
            officerCooldown = 5f;
        }

        void OnDestroy()
        {
            if (Officer) Destroy(Officer.gameObject);
        }
    }
}
