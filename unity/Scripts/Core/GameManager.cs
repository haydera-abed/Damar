using System;
using UnityEngine;

namespace Damar
{
    /// <summary>
    /// مدير اللعبة: المال المحمول، المال في المخبأ، الحفظ، الاعتقال وإعادة الظهور.
    /// ضعه على كائن فارغ اسمه GameManager في المشهد.
    /// </summary>
    [DefaultExecutionOrder(-100)]
    public class GameManager : MonoBehaviour
    {
        public static GameManager I { get; private set; }

        [Header("الاقتصاد")]
        public int goal = 250000;

        [Header("مراجع")]
        public PlayerController player;
        public Transform safehouseSpawn;

        [Header("الاعتقال")]
        [Tooltip("سرعة تناقص شريط الاعتقال عند الابتعاد عن الشرطة")]
        public float arrestDecay = 0.6f;

        public int Cash { get; private set; }
        public int Bank { get; private set; }
        public float ArrestProgress { get; private set; }
        public bool HasWon => Bank >= goal;

        /// <summary>يُستدعى عند الاعتقال مع المبلغ الذي صادرته الشرطة.</summary>
        public event Action<int> Busted;
        public event Action Won;

        const string SaveKey = "damar_bank";
        float arrestRate;
        bool winAnnounced;

        void Awake()
        {
            if (I != null && I != this) { Destroy(gameObject); return; }
            I = this;
            Bank = PlayerPrefs.GetInt(SaveKey, 0);
            winAnnounced = HasWon;
        }

        public void AddCash(int amount) => Cash += amount;

        /// <summary>إخفاء المال في المخبأ. يفشل إذا كانت الشرطة تلاحقك.</summary>
        public bool TryStash()
        {
            if (Cash <= 0 || WantedSystem.I.Level > 0) return false;
            Bank += Cash;
            Cash = 0;
            PlayerPrefs.SetInt(SaveKey, Bank);
            PlayerPrefs.Save();
            if (HasWon && !winAnnounced) { winAnnounced = true; Won?.Invoke(); }
            return true;
        }

        /// <summary>تستدعيه الشرطة كل إطار عندما تكون قادرة على اعتقالك.</summary>
        public void AddArrestPressure(float ratePerSecond) => arrestRate += ratePerSecond;

        void LateUpdate()
        {
            if (arrestRate > 0f) ArrestProgress = Mathf.Min(1f, ArrestProgress + arrestRate * Time.deltaTime);
            else ArrestProgress = Mathf.Max(0f, ArrestProgress - arrestDecay * Time.deltaTime);
            arrestRate = 0f;
            if (ArrestProgress >= 1f) Bust();
        }

        public void Bust()
        {
            int lost = Cash;
            Cash = 0;
            ArrestProgress = 0f;
            WantedSystem.I.Clear();
            if (PoliceSpawner.I != null) PoliceSpawner.I.DespawnChasers();
            player.Teleport(safehouseSpawn.position, safehouseSpawn.rotation);
            Busted?.Invoke(lost);
        }
    }
}
