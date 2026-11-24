using UnityEngine;

namespace Damar
{
    /// <summary>أضواء الشرطة الحمراء والزرقاء المتناوبة + صوت الصفارة أثناء المطاردة.</summary>
    public class SirenLights : MonoBehaviour
    {
        public Light redLight, blueLight;
        public float flashRate = 2.2f;
        public float intensity = 40f;
        public AudioSource siren;

        [Tooltip("اتركه فارغاً لتعمل الأضواء طوال الوقت")]
        public PoliceCarAI police;

        float phase;

        void Awake() { phase = Random.value; }

        void Update()
        {
            bool on = police == null || police.Chasing;
            bool red = ((Time.time * flashRate + phase) % 1f) < 0.5f;
            if (redLight) redLight.intensity = on && red ? intensity : 0f;
            if (blueLight) blueLight.intensity = on && !red ? intensity : 0f;
            if (siren)
            {
                if (on && !siren.isPlaying) siren.Play();
                else if (!on && siren.isPlaying) siren.Stop();
            }
        }
    }
}
