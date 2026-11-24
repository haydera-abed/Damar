using UnityEngine;

namespace Damar
{
    /// <summary>
    /// سيارة مدنية تتبع نقاط طريق (Waypoints) وتتوقف أمام العوائق.
    /// ضع نقاط الطريق كأبناء لكائن فارغ وارسلها في route بالترتيب (على مسار اليمين).
    /// </summary>
    [RequireComponent(typeof(VehicleController))]
    public class TrafficAI : MonoBehaviour, IVehicleAI
    {
        public Transform[] route;
        public float cruiseKmh = 40f;
        public float reachDistance = 6f;
        public float lookAhead = 9f;
        public LayerMask obstacleMask = ~0;

        VehicleController v;
        readonly DriveHelper drive = new DriveHelper();
        int index;
        float blockedTime, ignoreTime;

        void Awake()
        {
            v = GetComponent<VehicleController>();
            if (route != null && route.Length > 0) index = ClosestIndex();
        }

        public void SetEnabled(bool enabled) => this.enabled = enabled;

        int ClosestIndex()
        {
            int best = 0; float bd = float.MaxValue;
            for (int i = 0; i < route.Length; i++)
            {
                float d = (route[i].position - transform.position).sqrMagnitude;
                if (d < bd) { bd = d; best = i; }
            }
            return best;
        }

        void Update()
        {
            if (route == null || route.Length == 0) { DriveHelper.Stop(v); return; }
            float dt = Time.deltaTime;
            Vector3 target = route[index].position;
            if ((target - transform.position).Flat().magnitude < reachDistance) index = (index + 1) % route.Length;

            drive.DriveTowards(v, route[index].position, cruiseKmh, dt);

            if (ignoreTime > 0f) { ignoreTime -= dt; return; }
            // لا تضع طبقة الأرض/الطريق في obstacleMask
            Vector3 origin = transform.position + Vector3.up * 1f + transform.forward * 2.4f;
            if (Physics.SphereCast(origin, 0.8f, transform.forward, out _, lookAhead, obstacleMask, QueryTriggerInteraction.Ignore))
            {
                DriveHelper.Stop(v);
                blockedTime += dt;
                if (blockedTime > 4f) { ignoreTime = 2.5f; blockedTime = 0f; } // فك الاختناق في التقاطعات
            }
            else blockedTime = 0f;
        }
    }
}
