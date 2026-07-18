using UnityEngine;

public class FirstPersonController : MonoBehaviour
{
    [Header("移动设置")]
    public float walkSpeed = 5f;          // 移动速度
    public float upDownSpeed = 3f;        // 升降速度（Q/E） 

    [Header("鼠标视角设置")]
    public float mouseSensitivity = 2f;   // 鼠标灵敏度
    public float verticalLookLimit = 90f; // 上下视角限制（度）

    [Header("其他")]
    public bool lockCursor = true;        // 是否锁定并隐藏鼠标

    private float xRotation = 0f;          // 当前上下旋转角度
    private CharacterController controller; // 可选的CharacterController组件

    private void Start()
    {
        // 获取CharacterController（如果存在）
        controller = GetComponent<CharacterController>();

        // 锁定鼠标
        if (lockCursor)
        {
            Cursor.lockState = CursorLockMode.Locked;
            Cursor.visible = false;
        }
    }

    private void Update()
    {
        HandleMouseLook();
        HandleMovement();
        HandleElevation();

        // 可选：按ESC解锁鼠标（便于调试）
        if (Input.GetKeyDown(KeyCode.Escape))
        {
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;
        }
    }

    private void HandleMouseLook()
    {
        // 获取鼠标移动量
        float mouseX = Input.GetAxis("Mouse X") * mouseSensitivity;
        float mouseY = Input.GetAxis("Mouse Y") * mouseSensitivity;

        // 水平旋转：直接绕世界Y轴旋转物体
        transform.Rotate(Vector3.up, mouseX);

        // 垂直旋转：计算并限制角度，然后绕局部X轴旋转
        xRotation -= mouseY;
        xRotation = Mathf.Clamp(xRotation, -verticalLookLimit, verticalLookLimit);
        transform.localRotation = Quaternion.Euler(xRotation, transform.localEulerAngles.y, 0f);
    }

    private void HandleMovement()
    {
        // 获取WASD输入
        float horizontal = Input.GetAxis("Horizontal");
        float vertical = Input.GetAxis("Vertical");

        // 计算移动方向（水平移动时忽略相机的俯仰，只使用相机朝向的水平投影）
        Vector3 forward = transform.forward;
        Vector3 right = transform.right;
        forward.y = 0f;
        forward.Normalize();
        right.y = 0f;
        right.Normalize();

        Vector3 moveDirection = (forward * vertical + right * horizontal).normalized;

        // 应用移动
        Vector3 movement = moveDirection * walkSpeed * Time.deltaTime;

        if (controller != null)
        {
            controller.Move(movement);
        }
        else
        {
            transform.Translate(movement, Space.World);
        }
    }

    private void HandleElevation()
    {
        // 升降：Q下降，E上升
        float elevation = 0f;
        if (Input.GetKey(KeyCode.Q))
            elevation = -upDownSpeed;
        if (Input.GetKey(KeyCode.E))
            elevation = upDownSpeed;

        Vector3 elevationMovement = Vector3.up * elevation * Time.deltaTime;

        if (controller != null)
        {
            controller.Move(elevationMovement);
        }
        else
        {
            transform.Translate(elevationMovement, Space.World);
        }
    }
}