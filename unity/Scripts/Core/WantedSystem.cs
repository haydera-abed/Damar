using UnityEngine;

namespace Damar
{
    /// <summary>
    /// نظام النجوم (0–5). الشرطة تستدعي ReportSeen كلما رأت اللاعب؛
    /// إذا لم يرك أحد مدة كافية تنقص نجمة.
    /// </summary>
    [DefaultExecutionOrder(-90)]
    public class WantedSystem : MonoBehaviour
    {
        public static WantedSystem I { get; private set; }

        public const int MaxLevel = 5;

        [Tooltip("ثواني الاختباء الأساسية لخسارة نجمة")]
        public float baseLoseTime = 5f;
        [Tooltip("ثواني إضافية لكل نجمة")]
        public float perStarLoseTime = 2.5f;

        public int Level { get; private set; }
        public float UnseenTime { get; private set; }
        public float LoseTime => baseLoseTime + perStarLoseTime * Level;
        /// <summary>0..1 — تقدّم الاختفاء عن الأنظار (لشريط الواجهة).</summary>
        public float LoseProgress => Level > 0 ? Mathf.Clamp01(UnseenTime / LoseTime) : 0f;
        public bool IsHidden => Level > 0 && UnseenTime > 0.8f;

        public event System.Action<int> LevelChanged;

        bool seenThisFrame;

        void Awake() { I = this; }

        public void ReportSeen() => seenThisFrame = true;

        /// <summary>رفع النجوم إلى مستوى معين على الأقل.</summary>
        public void RaiseTo(int level)
        {
            level = Mathf.Clamp(level, 0, MaxLevel);
            if (level <= Level) return;
            Level = level;
            UnseenTime = 0f;
            LevelChanged?.Invoke(Level);
        }

        public void Add(int stars) => RaiseTo(Level + stars);

        public void Clear()
        {
            if (Level == 0) return;
            Level = 0;
            UnseenTime = 0f;
            LevelChanged?.Invoke(0);
        }

        void LateUpdate()
        {
            if (Level == 0) { seenThisFrame = false; return; }
            if (seenThisFrame) UnseenTime = 0f; else UnseenTime += Time.deltaTime;
            seenThisFrame = false;
            if (UnseenTime > LoseTime)
            {
                Level--;
                UnseenTime = 0f;
                LevelChanged?.Invoke(Level);
            }
        }
    }
}
