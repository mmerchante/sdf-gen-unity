using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class SDFOperation : MonoBehaviour
{
    public enum OperationType
    {
        Union = 0,
        Substraction = 1,
        Intersection = 2,
    }
    public enum DomainDistortion
    {
        None = 0,
        Repeat3D = 1,
        RepeatX = 2,
        RepeatY = 3,
        RepeatZ = 4,
        RepeatPolarX = 5,
        RepeatPolarY = 6,
        RepeatPolarZ = 7,
        MirrorXYZ = 8,
        MirrorXZ = 9,
        MirrorX = 10,
        MirrorY = 11,
        MirrorZ = 12
    }

    public string customName = "";
    public OperationType operationType = OperationType.Union;
    public DomainDistortion distortionType = DomainDistortion.None;

    public Vector3 domainRepeat = Vector3.one;
    
    public void Update()
    {
        this.name = operationType.ToString();

        if(!string.IsNullOrEmpty(customName))
            this.name += "-" + customName;
    }
}