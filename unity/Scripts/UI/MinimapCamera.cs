using UnityEngine;

namespace Damar
{
    /// <summary>
    /// كاميرا علوية Orthographic تتبع اللاعب وتدور مع الكاميرا الرئيسية.
    /// اجعل مخرجها Render Texture واعرضها في RawImage دائري داخل الواجهة.
    /// </summary>
    [RequireComponent(typeof(Camera))]
    public class MinimapCamera : MonoBehaviour
    {
        public Transform mainCamera;
        public float height = 120f;
        public bool rotateWithCamera = true;

        void LateUpdate()
        {
            var gm = GameManager.I;
            if (gm == null || gm.player == null) return;
            Vector3 p = gm.player.Position;
            transform.position = new Vector3(p.x, p.y + height, p.z);
            float yaw = rotateWithCamera && mainCamera ? mainCamera.eulerAngles.y : 0f;
            transform.rotation = Quaternion.Euler(90f, yaw, 0f);
        }
    }
}
