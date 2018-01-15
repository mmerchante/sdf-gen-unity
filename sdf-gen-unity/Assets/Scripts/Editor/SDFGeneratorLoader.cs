using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;

[InitializeOnLoad]
public class SDFGeneratorLoader
{
    [MenuItem("GameObject/Create Other/SDF Shape")]
    public static void CreateSDFShape()
    {
        GameObject go = new GameObject();
        go.AddComponent<SDFShape>();

        if (Selection.objects.Length == 1)
            go.transform.parent = Selection.activeGameObject.transform;

        go.transform.localPosition = Vector3.zero;
        go.transform.localRotation = Quaternion.identity;
        go.transform.localScale = Vector3.one;
    }

    [MenuItem("GameObject/Create Other/SDF Operation")]
    public static void CreateSDFOperation()
    {
        GameObject go = new GameObject();
        go.AddComponent<SDFOperation>();

        if (Selection.objects.Length == 1)
            go.transform.parent = Selection.activeGameObject.transform;
        else if(Selection.objects.Length > 1)
        {
            // TODO: Compose selected as children
        }

        go.transform.localPosition = Vector3.zero;
        go.transform.localRotation = Quaternion.identity;
        go.transform.localScale = Vector3.one;
    }

    static SDFGeneratorLoader()
    {
        EditorApplication.update -= UpdateRaymarcher;
        EditorApplication.update += UpdateRaymarcher;

        Undo.postprocessModifications -= OnPostProcessModifications;
        Undo.postprocessModifications += OnPostProcessModifications;

        Undo.undoRedoPerformed -= UpdateRaymarcher;
        Undo.undoRedoPerformed += UpdateRaymarcher;
    }

    static UndoPropertyModification[] OnPostProcessModifications(UndoPropertyModification[] propertyModifications)
    {
        SDFGenerator[] generators = GameObject.FindObjectsOfType<SDFGenerator>();

        foreach (SDFGenerator g in generators)
            g.UpdateRaymarcher(true);

        return propertyModifications;
    }

    static public void UpdateRaymarcher()
    {
        SDFGenerator[] generators = GameObject.FindObjectsOfType<SDFGenerator>();

        foreach(SDFGenerator g in generators)
            g.UpdateRaymarcher(false);
    }
}
