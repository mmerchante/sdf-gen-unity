using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;

[InitializeOnLoad]
public class SDFGeneratorLoader
{
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
