using UnityEngine;
using UnityEngine.AI;

namespace Damar
{
    /// <summary>
    /// شرطي راجل ينزل من السيارة ويلاحق اللاعب ثم يعود إليها.
    /// الإعداد: NavMeshAgent (السرعة 6.9) + نموذج شرطي بـ Animator فيه Speed (float) و Arresting (bool).
    /// </summary>
    [RequireComponent(typeof(NavMeshAgent))]
    public class PoliceOfficerAI : MonoBehaviour
    {
        public float chaseSpeed = 6.9f;
        public float returnSpeed = 5f;
        public float arrestRange = 1.8f;
        public float arrestRate = 0.75f;
        public float sightRange = 35f;
        public Animator animator;

        static readonly int SpeedHash = Animator.StringToHash("Speed");
        static readonly int ArrestingHash = Animator.StringToHash("Arresting");

        NavMeshAgent agent;
        PoliceCarAI car;
        PlayerController player;
        bool returning;
        float repath;

        public void Init(PoliceCarAI owner)
        {
            car = owner;
            player = GameManager.I.player;
            agent = GetComponent<NavMeshAgent>();
            agent.speed = chaseSpeed;
        }

        public void ReturnToCar() => returning = true;

        void Update()
        {
            if (car == null) { Destroy(gameObject); return; }
            float dt = Time.deltaTime;
            float dPlayer = Vector3.Distance(transform.position, player.Position);

            if (WantedSystem.I.Level == 0 || (!player.OnFoot && dPlayer > 5f)) returning = true;

            repath -= dt;
            if (repath <= 0f)
            {
                repath = 0.25f;
                agent.speed = returning ? returnSpeed : chaseSpeed;
                agent.SetDestination(returning ? car.transform.position : player.Position);
            }

            bool arresting = false;
            if (!returning)
            {
                if (dPlayer < sightRange) WantedSystem.I.ReportSeen();
                if (dPlayer < arrestRange) { GameManager.I.AddArrestPressure(arrestRate); arresting = true; }
                else if (!player.OnFoot && dPlayer < 3.3f && player.CurrentVehicle.SpeedKmh < 10f) { GameManager.I.AddArrestPressure(0.5f); arresting = true; }
            }
            else if (Vector3.Distance(transform.position, car.transform.position) < 2.8f)
            {
                car.OnOfficerReturned();
                Destroy(gameObject);
                return;
            }

            if (animator)
            {
                animator.SetFloat(SpeedHash, agent.velocity.magnitude, 0.1f, dt);
                animator.SetBool(ArrestingHash, arresting);
            }
        }
    }
}
