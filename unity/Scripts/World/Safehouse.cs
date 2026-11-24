using UnityEngine;

namespace Damar
{
    /// <summary>المخبأ: اضغط E داخل النطاق لإخفاء المال. لا يعمل والشرطة تلاحقك.</summary>
    public class Safehouse : MonoBehaviour
    {
        public float radius = 3.6f;
        public AudioClip stashSound;

        public static event System.Action<int> Stashed;
        public static event System.Action StashRefused;

        PlayerController player;

        void Start() { player = GameManager.I.player; }

        public bool PlayerInRange => player != null && player.OnFoot &&
                                     (player.Position - transform.position).Flat().magnitude < radius;

        void Update()
        {
            if (!PlayerInRange || !Input.GetKeyDown(KeyCode.E) || GameManager.I.Cash <= 0) return;
            int amount = GameManager.I.Cash;
            if (GameManager.I.TryStash())
            {
                if (stashSound) AudioSource.PlayClipAtPoint(stashSound, transform.position);
                Stashed?.Invoke(amount);
            }
            else StashRefused?.Invoke();
        }

        void OnDrawGizmos()
        {
            Gizmos.color = Color.green;
            Gizmos.DrawWireSphere(transform.position, radius);
        }
    }
}
