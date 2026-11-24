using System.Collections.Generic;
using UnityEngine;
using UnityEngine.AI;

namespace Damar
{
    /// <summary>
    /// يُظهر سيارات الشرطة بعيداً عن اللاعب حسب عدد النجوم، ويزيلها عند انتهاء المطاردة.
    /// </summary>
    public class PoliceSpawner : MonoBehaviour
    {
        public static PoliceSpawner I { get; private set; }

        public PoliceCarAI policeCarPrefab;
        [Tooltip("عدد سيارات المطاردة لكل مستوى نجوم 0..5")]
        public int[] carsPerLevel = { 0, 2, 3, 5, 7, 9 };
        public float spawnInterval = 2.2f;
        public float minSpawnDistance = 110f, maxSpawnDistance = 190f;
        public float despawnDistance = 90f;
        public string roadAreaName = "Road";

        readonly List<PoliceCarAI> cars = new List<PoliceCarAI>();
        float timer;
        int roadMask;

        void Awake()
        {
            I = this;
            int area = NavMesh.GetAreaFromName(roadAreaName);
            roadMask = area >= 0 ? 1 << area : NavMesh.AllAreas;
        }

        public bool AnyPoliceSees(Vector3 pos)
        {
            foreach (var c in cars) if (c && c.CanSee(pos)) return true;
            return false;
        }

        void Update()
        {
            cars.RemoveAll(c => c == null);
            Vector3 p = GameManager.I.player.Position;
            int level = WantedSystem.I.Level;

            if (level == 0)
            {
                for (int i = cars.Count - 1; i >= 0; i--)
                    if (Vector3.Distance(cars[i].transform.position, p) > despawnDistance) { Destroy(cars[i].gameObject); cars.RemoveAt(i); }
                return;
            }

            timer -= Time.deltaTime;
            if (cars.Count < carsPerLevel[Mathf.Clamp(level, 0, carsPerLevel.Length - 1)] && timer <= 0f)
            {
                timer = spawnInterval;
                TrySpawn(p);
            }
        }

        void TrySpawn(Vector3 around)
        {
            for (int attempt = 0; attempt < 12; attempt++)
            {
                Vector2 dir = Random.insideUnitCircle.normalized;
                float dist = Random.Range(minSpawnDistance, maxSpawnDistance);
                Vector3 guess = around + new Vector3(dir.x, 0f, dir.y) * dist;
                if (!NavMesh.SamplePosition(guess, out NavMeshHit hit, 25f, roadMask)) continue;
                if (Physics.CheckSphere(hit.position + Vector3.up * 2f, 1.5f, ~0, QueryTriggerInteraction.Ignore)) continue; // المكان مشغول بسيارة
                Quaternion face = Quaternion.LookRotation((around - hit.position).Flat());
                var car = Instantiate(policeCarPrefab, hit.position + Vector3.up * 0.3f, face);
                cars.Add(car);
                return;
            }
        }

        /// <summary>عند الاعتقال: إزالة كل سيارات المطاردة.</summary>
        public void DespawnChasers()
        {
            foreach (var c in cars) if (c) Destroy(c.gameObject);
            cars.Clear();
        }
    }
}
