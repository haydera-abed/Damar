using UnityEngine;

namespace Damar
{
    /// <summary>
    /// متجر/بنك قابل للسرقة. ضعه على كائن أمام باب المتجر (نقطة السرقة).
    /// اضغط E مطولاً داخل النطاق للسرقة.
    /// </summary>
    public class Store : MonoBehaviour
    {
        public enum Kind { Supermarket, GasStation, Jewelry, Bank }

        public Kind kind = Kind.Supermarket;
        public string displayName = "سوبرماركت";
        public Vector2Int valueRange = new Vector2Int(700, 1600);
        [Tooltip("ثوانٍ لإتمام السرقة")] public float robTime = 4f;
        [Tooltip("النجوم عند انطلاق الإنذار")] [Range(1, 5)] public int heat = 1;
        [Tooltip("ثوانٍ قبل أن يمكن سرقته مجدداً")] public float cooldown = 60f;
        public float radius = 3.2f;

        [Header("مؤثرات (اختياري)")]
        public GameObject openVisuals;  // اللافتة المضيئة، دائرة الأرض، عمود الضوء...
        public AudioSource alarm;
        public AudioClip cashSound;

        public float Progress { get; private set; }
        public float CooldownLeft { get; private set; }
        public bool IsOpen => CooldownLeft <= 0f;
        public bool IsBeingRobbed => Progress > 0f;

        public static event System.Action<Store, int> Robbed;

        PlayerController player;

        void Start() { player = GameManager.I.player; }

        public static Store Preset(Store s, Kind k)
        {
            s.kind = k;
            switch (k)
            {
                case Kind.Supermarket: s.displayName = "سوبرماركت"; s.valueRange = new Vector2Int(700, 1600); s.robTime = 4f; s.heat = 1; s.cooldown = 60f; break;
                case Kind.GasStation: s.displayName = "محطة وقود"; s.valueRange = new Vector2Int(1100, 2600); s.robTime = 5f; s.heat = 2; s.cooldown = 75f; break;
                case Kind.Jewelry: s.displayName = "مجوهرات"; s.valueRange = new Vector2Int(7000, 15000); s.robTime = 7f; s.heat = 3; s.cooldown = 120f; break;
                case Kind.Bank: s.displayName = "البنك المركزي"; s.valueRange = new Vector2Int(30000, 60000); s.robTime = 10f; s.heat = 5; s.cooldown = 200f; break;
            }
            return s;
        }

        void Reset() => Preset(this, kind);

        [ContextMenu("تطبيق إعدادات النوع (Apply Kind Preset)")]
        void ApplyPreset() => Preset(this, kind);

        public bool PlayerInRange => player != null && player.OnFoot &&
                                     (player.Position - transform.position).Flat().magnitude < radius;

        void Update()
        {
            if (CooldownLeft > 0f)
            {
                CooldownLeft -= Time.deltaTime;
                if (CooldownLeft <= 0f && openVisuals) openVisuals.SetActive(true);
            }

            bool robbing = IsOpen && PlayerInRange && Input.GetKey(KeyCode.E);
            if (robbing)
            {
                if (Progress == 0f)
                {
                    WantedSystem.I.RaiseTo(heat);
                    if (alarm) alarm.Play();
                }
                Progress += Time.deltaTime / robTime;
                player.IsRobbing = true;
                Vector3 look = (transform.position - player.transform.position).Flat();
                if (look.sqrMagnitude > 0.01f) player.transform.rotation = Quaternion.LookRotation(look);
                if (Progress >= 1f) Complete();
            }
            else if (Progress > 0f)
            {
                Progress = 0f; // السرقة فشلت
                if (player) player.IsRobbing = false;
            }
        }

        void Complete()
        {
            int amount = Mathf.RoundToInt(Random.Range(valueRange.x, valueRange.y) / 10f) * 10;
            GameManager.I.AddCash(amount);
            WantedSystem.I.RaiseTo(Mathf.Min(WantedSystem.MaxLevel, heat + (heat >= 3 ? 1 : 0)));
            Progress = 0f;
            CooldownLeft = cooldown;
            player.IsRobbing = false;
            if (openVisuals) openVisuals.SetActive(false);
            if (cashSound) AudioSource.PlayClipAtPoint(cashSound, transform.position);
            Robbed?.Invoke(this, amount);
        }

        void OnDrawGizmos()
        {
            Gizmos.color = IsOpen ? new Color(0.2f, 1f, 0.6f, 0.6f) : Color.gray;
            Gizmos.DrawWireSphere(transform.position, radius);
        }
    }
}
