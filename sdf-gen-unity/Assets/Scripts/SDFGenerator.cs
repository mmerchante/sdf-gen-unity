using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.SceneManagement;


[ExecuteInEditMode]
public class SDFGenerator : MonoBehaviour
{
    private const int MAX_SHAPES = 128;

    public MeshRenderer quadRenderer;

    private Material material;
    private ComputeBuffer nodeBuffer;
    private RenderTexture accumulationBuffer;

    private Camera currentCamera;
    private Matrix4x4 camTransform;

    public struct Node
    {
        public Matrix4x4 transform;
        public int type;
        public int parameters;
        public int depth;
        public int domainDistortionType;
        public Vector3 domainDistortion;
    }

    public void Awake()
    {
        this.material = quadRenderer.sharedMaterial;
    }
    
    private void RebuildSceneData()
    {
        SDFShape[] shapes = GetComponentsInChildren<SDFShape>();
        int count = Mathf.Min(MAX_SHAPES, shapes.Length);

        List<Node> tree = new List<Node>();
        BuildNodeTree(this.gameObject, tree, 0);

        if (nodeBuffer == null)
        {
            int nodeSize = System.Runtime.InteropServices.Marshal.SizeOf(typeof(Node));
            this.nodeBuffer = new ComputeBuffer(MAX_SHAPES, nodeSize, ComputeBufferType.Default);
        }

        this.nodeBuffer.SetData(tree.ToArray());

        material.SetBuffer("_SceneTree", this.nodeBuffer);
        material.SetInt("_SDFShapeCount", tree.Count);
    }

    public void OnDestroy()
    {
        if(nodeBuffer != null)
            nodeBuffer.Release();
    }

    private void RebuildAccumulationBuffer(bool force)
    {
        Camera cam = Camera.current;

        if (cam)
        {
            int pixels = (int)(cam.pixelRect.width * cam.pixelRect.height);

            if (force || camTransform != cam.transform.localToWorldMatrix || accumulationBuffer == null || accumulationBuffer.width * accumulationBuffer.height != pixels)
            {
                currentCamera = cam;

                if (accumulationBuffer != null)
                {
                    accumulationBuffer.Release();
                    DestroyImmediate(accumulationBuffer);
                    System.GC.Collect();
                }

                accumulationBuffer = new RenderTexture((int)cam.pixelRect.width, (int)cam.pixelRect.height, 0, RenderTextureFormat.RFloat);
                accumulationBuffer.useMipMap = false;
                accumulationBuffer.autoGenerateMips = false;
                accumulationBuffer.enableRandomWrite = true;
                accumulationBuffer.Create();

                material.SetTexture("_AccumulationBuffer", accumulationBuffer);

                camTransform = cam.transform.localToWorldMatrix;

                if (accumulationBuffer)
                {
                    Graphics.SetRandomWriteTarget(1, accumulationBuffer);
                    //Graphics.SetRenderTarget(null);
                    //Graphics.ClearRandomWriteTargets();
                }

                Debug.Log("Updating...");
            }
        }
    }

    private void BuildNodeTree(GameObject go, List<Node> nodeList, int depth)
    {
        if (!go.activeInHierarchy)
            return;

        SDFOperation op = go.GetComponent<SDFOperation>();
        SDFShape shape = go.GetComponent<SDFShape>();

        Node node = new Node();
        node.transform = Matrix4x4.TRS(go.transform.localPosition, go.transform.localRotation, go.transform.localScale).inverse;
        node.type = 0;
        node.depth = depth;
        node.domainDistortionType = 0;
        node.domainDistortion = Vector3.one;

        if (op)
        {
            node.type = 0;
            node.parameters = (int)op.operationType;
            node.domainDistortionType = (int)op.distortionType;
            node.domainDistortion = op.domainRepeat; // For now...
        }
        else if (shape)
        {
            node.type = 1;
            node.parameters = (int)shape.shapeType;
        }

        nodeList.Add(node);

        foreach(Transform child in go.transform)
            BuildNodeTree(child.gameObject, nodeList, depth+1);
    }

    public void LateUpdate()
    {
        RebuildSceneData();
    }

    public void UpdateRaymarcher(bool force)
    {
        RebuildAccumulationBuffer(force);
    }
}
