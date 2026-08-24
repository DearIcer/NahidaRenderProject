using UnityEngine;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine.Rendering.Universal;
using System.IO;

// 批处理截图：编辑模式下用临时 Base 相机渲染（Overlay 相机单独 Render 无输出）
public static class BatchScreenshot
{
    // 验证用：把主光转到角色正侧方（toward-light ≈ 屏幕右侧），截 unity_side_right.png
    public static void CaptureSideLight()
    {
        EditorSceneManager.OpenScene("Assets/Scenes/SampleScene.unity");

        foreach (var t in Object.FindObjectsOfType<Transform>(true))
        {
            if (t.name == "NahidaMMDModel" || t.name == "FurinaMMD" || t.name == "Avatar_Girl_Sword_Furina")
            {
                t.gameObject.SetActive(false);
            }
        }
        foreach (var li in Object.FindObjectsOfType<Light>())
        {
            if (li.type == LightType.Directional)
            {
                li.transform.rotation = Quaternion.Euler(15f, 90f, 0f);
                Debug.Log("[BatchScreenshot] SideLight forward=" + li.transform.forward);
            }
        }
        var go = new GameObject("TempCaptureCamera");
        var cam = go.AddComponent<Camera>();
        cam.clearFlags = CameraClearFlags.Skybox;
        cam.cullingMask = 55;
        cam.fieldOfView = 43f;
        cam.nearClipPlane = 0.3f;
        cam.farClipPlane = 1000f;
        go.transform.position = new Vector3(0f, 0.81f, 1.8f);
        go.transform.rotation = Quaternion.Euler(0f, 180f, 0f);
        var data = cam.GetUniversalAdditionalCameraData();
        data.renderPostProcessing = true;

        const int w = 1141, h = 1016;
        var rt = new RenderTexture(w, h, 24, RenderTextureFormat.ARGB32);
        cam.targetTexture = rt;
        cam.Render();
        RenderTexture.active = rt;
        var tex = new Texture2D(w, h, TextureFormat.RGB24, false);
        tex.ReadPixels(new Rect(0, 0, w, h), 0, 0);
        tex.Apply();
        File.WriteAllBytes("E:\\UnityProject\\NahidaRenderProject\\unity_side_right.png", tex.EncodeToPNG());
        Debug.Log("[BatchScreenshot] saved unity_side_right.png");

        cam.targetTexture = null;
        RenderTexture.active = null;
        Object.DestroyImmediate(go);
        EditorApplication.Exit(0);
    }

    public static void Capture()
    {
        EditorSceneManager.OpenScene("Assets/Scenes/SampleScene.unity");

        foreach (var t in Object.FindObjectsOfType<Transform>(true))
        {
            if (t.name == "NahidaMMDModel" || t.name == "FurinaMMD" || t.name == "Avatar_Girl_Sword_Furina")
            {
                t.gameObject.SetActive(false);
            }
        }

        foreach (var smr in Object.FindObjectsOfType<SkinnedMeshRenderer>())
        {
            if (smr.sharedMesh != null && smr.sharedMesh.vertexCount > 0 && smr.name == "Body")
            {
                var smesh = smr.sharedMesh;
                int agree = 0, disagree = 0;
                for (int sub = 0; sub < smesh.subMeshCount; sub++)
                {
                    var tris = smesh.GetTriangles(sub);
                    for (int t = 0; t < tris.Length; t += 300)
                    {
                        var a = smesh.vertices[tris[t]];
                        var b = smesh.vertices[tris[t + 1]];
                        var c = smesh.vertices[tris[t + 2]];
                        var fn = Vector3.Cross(b - a, c - a);
                        var vn = smesh.normals[tris[t]] + smesh.normals[tris[t + 1]] + smesh.normals[tris[t + 2]];
                        if (Vector3.Dot(fn, vn) > 0) agree++; else disagree++;
                    }
                }
                Debug.Log("[BatchScreenshot] Body winding agree=" + agree + " disagree=" + disagree);
                // 导出 UV0+UV2 供 Godot 端注入
                var uv0 = smesh.uv;
                var uv2 = smesh.uv2;
                using (var fs = new FileStream("E:\\UnityProject\\NahidaRenderProject\\body_uv2.bin", FileMode.Create))
                using (var bw = new BinaryWriter(fs))
                {
                    bw.Write(smesh.vertexCount);
                    for (int vi = 0; vi < smesh.vertexCount; vi++)
                    {
                        bw.Write(uv0[vi].x); bw.Write(uv0[vi].y);
                        bw.Write(uv2.Length > vi ? uv2[vi].x : 0f);
                        bw.Write(uv2.Length > vi ? uv2[vi].y : 0f);
                    }
                }
                Debug.Log("[BatchScreenshot] dumped body_uv2.bin verts=" + smesh.vertexCount + " uv2len=" + smesh.uv2.Length);
            }
        }
        var go = new GameObject("TempCaptureCamera");
        // 打印模型实际包围盒与主光方向，供 Godot 端对齐
        foreach (var smr in Object.FindObjectsOfType<SkinnedMeshRenderer>())
        {
            if (smr.name == "Body")
            {
                Debug.Log("[BatchScreenshot] Body bounds: center=" + smr.bounds.center + " size=" + smr.bounds.size);
            }
        }
        foreach (var li in Object.FindObjectsOfType<Light>())
        {
            if (li.type == LightType.Directional)
            {
                Debug.Log("[BatchScreenshot] Light forward=" + li.transform.forward + " color=" + li.color + " intensity=" + li.intensity);
            }
        }
        var cam = go.AddComponent<Camera>();
        cam.clearFlags = CameraClearFlags.Skybox;
        cam.cullingMask = 55;
        cam.fieldOfView = 43f;
        cam.nearClipPlane = 0.3f;
        cam.farClipPlane = 1000f;
        go.transform.position = new Vector3(0f, 0.81f, 1.8f);
        go.transform.rotation = Quaternion.Euler(0f, 180f, 0f);
        var data = cam.GetUniversalAdditionalCameraData();
        data.renderPostProcessing = true;

        const int w = 1141, h = 1016;
        var rt = new RenderTexture(w, h, 24, RenderTextureFormat.ARGB32);
        cam.targetTexture = rt;
        cam.Render();
        RenderTexture.active = rt;
        var tex = new Texture2D(w, h, TextureFormat.RGB24, false);
        tex.ReadPixels(new Rect(0, 0, w, h), 0, 0);
        tex.Apply();
        File.WriteAllBytes("E:\\UnityProject\\NahidaRenderProject\\unity_reference.png", tex.EncodeToPNG());
        Debug.Log("[BatchScreenshot] saved unity_reference.png");

        cam.targetTexture = null;
        RenderTexture.active = null;
        Object.DestroyImmediate(go);
        EditorApplication.Exit(0);
    }
}
