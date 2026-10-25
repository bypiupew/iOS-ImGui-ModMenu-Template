
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#import "Esp/CaptainHook.h"
#import "Esp/ImGuiDrawView.h"
#import "IMGUI/imgui.h"
#import "IMGUI/imgui_impl_metal.h"
#import "IMGUI/Honkai.h"

#define kWidth  [UIScreen mainScreen].bounds.size.width
#define kHeight [UIScreen mainScreen].bounds.size.height
#define kScale  [UIScreen mainScreen].scale

@interface ImGuiDrawView () <MTKViewDelegate>

@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;

@end

@implementation ImGuiDrawView

static BOOL MenDeal = NO;
static BOOL ImGuiInitialized = NO;

static bool esp_boxes = false;
static bool esp_health = false;
static bool esp_distance = false;
static bool esp_skeleton = false;

static bool aim_assist = false;
static bool aim_triggerbot = false;
static float aim_fov = 80.0f;
static float aim_smooth = 5.0f;

static bool move_jumphack = false;
static bool move_parachute = false;
static bool move_autoclimb = false;
static bool move_walkthrough = false;
static bool move_underwater = false;

static bool misc_antispectate = false;
static bool misc_grave = false;

#pragma mark - Initialization

- (instancetype)initWithNibName:(NSString *)nibNameOrNil
                          bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil
                           bundle:nibBundleOrNil];

    if (self == nil) {
        return nil;
    }

    _device = MTLCreateSystemDefaultDevice();

    if (_device == nil) {
        return nil;
    }

    _commandQueue = [_device newCommandQueue];

    if (_commandQueue == nil) {
        return nil;
    }

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();

    ImGuiIO &io = ImGui::GetIO();
    io.IniFilename = nullptr;

    ImGui::StyleColorsDark();

    if (Honkai_compressed_data != nullptr &&
        Honkai_compressed_size > 0) {
        io.Fonts->AddFontFromMemoryCompressedTTF(
            (void *)Honkai_compressed_data,
            Honkai_compressed_size,
            38.0f,
            nullptr,
            io.Fonts->GetGlyphRangesDefault()
        );
    }

    ImGui_ImplMetal_Init(_device);
    ImGuiInitialized = true;

    return self;
}

#pragma mark - Menu visibility

+ (void)showChange:(BOOL)open
{
    MenDeal = open;
}

+ (void)handleShowMenu:(UITapGestureRecognizer *)gesture
{
    (void)gesture;
    MenDeal = YES;
}

+ (void)handleHideMenu:(UITapGestureRecognizer *)gesture
{
    (void)gesture;
    MenDeal = NO;
}

#pragma mark - View lifecycle

- (void)loadView
{
    CGRect frame = UIScreen.mainScreen.bounds;

    MTKView *metalView =
        [[MTKView alloc] initWithFrame:frame
                                device:self.device];

    metalView.clearColor =
        MTLClearColorMake(0.0, 0.0, 0.0, 0.0);

    metalView.opaque = NO;
    metalView.backgroundColor = UIColor.clearColor;
    metalView.clipsToBounds = YES;
    metalView.preferredFramesPerSecond = 60;

    self.view = metalView;
}

- (MTKView *)mtkView
{
    return (MTKView *)self.view;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.mtkView.device = self.device;
    self.mtkView.delegate = self;

    self.view.backgroundColor = UIColor.clearColor;
    self.view.multipleTouchEnabled = YES;

    self.view.userInteractionEnabled = MenDeal;
    self.mtkView.userInteractionEnabled = MenDeal;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    self.mtkView.frame = self.view.bounds;
}

#pragma mark - Touch handling

- (void)updateIOWithTouchEvent:(UIEvent *)event
{
    if (!MenDeal || !ImGuiInitialized) {
        return;
    }

    ImGuiIO &io = ImGui::GetIO();

    UITouch *touch = event.allTouches.anyObject;

    if (touch != nil) {
        CGPoint location = [touch locationInView:self.view];
        io.MousePos = ImVec2(
            (float)location.x,
            (float)location.y
        );
    }

    BOOL activeTouch = NO;

    for (UITouch *item in event.allTouches) {
        if (item.phase != UITouchPhaseEnded &&
            item.phase != UITouchPhaseCancelled) {
            activeTouch = YES;
            break;
        }
    }

    io.MouseDown[0] = activeTouch;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches
          withEvent:(UIEvent *)event
{
    [self updateIOWithTouchEvent:event];
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    [self updateIOWithTouchEvent:event];
    [super touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    [self updateIOWithTouchEvent:event];
    [super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches
               withEvent:(UIEvent *)event
{
    [self updateIOWithTouchEvent:event];
    [super touchesCancelled:touches withEvent:event];
}

#pragma mark - Menu drawing

- (void)drawMenu
{
    ImGuiIO &io = ImGui::GetIO();

    ImGui::SetNextWindowPos(
        ImVec2(
            (io.DisplaySize.x - 420.0f) * 0.5f,
            (io.DisplaySize.y - 420.0f) * 0.5f
        ),
        ImGuiCond_FirstUseEver
    );

    ImGui::SetNextWindowSize(
        ImVec2(420.0f, 420.0f),
        ImGuiCond_FirstUseEver
    );

    ImGui::PushStyleColor(
        ImGuiCol_TitleBgActive,
        ImVec4(0.8f, 0.1f, 0.1f, 1.0f)
    );

    ImGui::PushStyleColor(
        ImGuiCol_Tab,
        ImVec4(0.2f, 0.2f, 0.2f, 1.0f)
    );

    ImGui::PushStyleColor(
        ImGuiCol_TabActive,
        ImVec4(0.8f, 0.1f, 0.1f, 1.0f)
    );

    bool visible = MenDeal;

    if (ImGui::Begin(
        "ROS MOD MENU | 3-Finger Double Tap",
        &visible
    )) {
        ImGui::Text("FPS: %.1f", io.Framerate);
        ImGui::Separator();

        if (ImGui::BeginTabBar("MainTabs")) {

            if (ImGui::BeginTabItem("ESP")) {
                ImGui::Checkbox("Player Boxes", &esp_boxes);
                ImGui::Checkbox("Health Bars", &esp_health);
                ImGui::Checkbox("Distance", &esp_distance);
                ImGui::Checkbox("Skeleton", &esp_skeleton);
                ImGui::EndTabItem();
            }

            if (ImGui::BeginTabItem("Aim")) {
                ImGui::Checkbox("Aim Assist", &aim_assist);
                ImGui::Checkbox("Triggerbot", &aim_triggerbot);

                ImGui::SliderFloat(
                    "FOV", &aim_fov, 10.0f, 300.0f
                );

                ImGui::SliderFloat(
                    "Smooth", &aim_smooth, 1.0f, 20.0f
                );

                ImGui::EndTabItem();
            }

            if (ImGui::BeginTabItem("Move")) {
                ImGui::Checkbox("Jump Hack", &move_jumphack);
                ImGui::Checkbox("Fast Parachute", &move_parachute);
                ImGui::Checkbox("Auto Climb", &move_autoclimb);
                ImGui::Checkbox("Walkthrough Walls", &move_walkthrough);
                ImGui::Checkbox("Underwater", &move_underwater);
                ImGui::EndTabItem();
            }

            if (ImGui::BeginTabItem("Misc")) {
                ImGui::Checkbox("Anti-Spectate", &misc_antispectate);
                ImGui::Checkbox("Grave", &misc_grave);
                ImGui::EndTabItem();
            }

            ImGui::EndTabBar();
        }

        ImGui::Separator();

        if (ImGui::Button("Close Menu")) {
            visible = false;
        }
    }

    ImGui::End();

    MenDeal = visible;

    ImGui::PopStyleColor(3);
}

#pragma mark - Metal rendering

- (void)drawInMTKView:(MTKView *)view
{
    if (!ImGuiInitialized ||
        self.commandQueue == nil ||
        view == nil) {
        return;
    }

    MTLRenderPassDescriptor *descriptor =
        view.currentRenderPassDescriptor;

    id<CAMetalDrawable> drawable =
        view.currentDrawable;

    if (descriptor == nil || drawable == nil) {
        return;
    }

    id<MTLCommandBuffer> commandBuffer =
        [self.commandQueue commandBuffer];

    if (commandBuffer == nil) {
        return;
    }

    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer renderCommandEncoderWithDescriptor:descriptor];

    if (encoder == nil) {
        return;
    }

    ImGuiIO &io = ImGui::GetIO();

    io.DisplaySize = ImVec2(
        (float)view.bounds.size.width,
        (float)view.bounds.size.height
    );

    CGFloat scale = view.window.screen.scale;

    if (scale <= 0.0) {
        scale = UIScreen.mainScreen.scale;
    }

    io.DisplayFramebufferScale = ImVec2(
        (float)scale,
        (float)scale
    );

    io.DeltaTime = 1.0f /
        (float)(view.preferredFramesPerSecond > 0
                    ? view.preferredFramesPerSecond
                    : 60);

    ImGui_ImplMetal_NewFrame(descriptor);
    ImGui::NewFrame();

    if (MenDeal) {
        [self drawMenu];
    }

    ImGui::Render();

    ImGui_ImplMetal_RenderDrawData(
        ImGui::GetDrawData(),
        commandBuffer,
        encoder
    );

    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

- (void)mtkView:(MTKView *)view
drawableSizeWillChange:(CGSize)size
{
    (void)view;
    (void)size;
}

#pragma mark - Cleanup

- (void)dealloc
{
    if (ImGuiInitialized) {
        ImGui_ImplMetal_Shutdown();
        ImGuiInitialized = false;
        ImGui::DestroyContext();
    }
}

@end
