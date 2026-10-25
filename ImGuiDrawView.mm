
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <Foundation/Foundation.h>

#import "Esp/ImGuiDrawView.h"
#import "IMGUI/imgui.h"
#import "IMGUI/imgui_impl_metal.h"
#import "IMGUI/Honkai.h"

static bool MenDeal = true;

@interface ImGuiDrawView () <MTKViewDelegate>

@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) UITapGestureRecognizer *toggleGesture;

@end

@implementation ImGuiDrawView

#pragma mark - Initialization

- (instancetype)initWithNibName:(NSString *)nibNameOrNil
                          bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil
                           bundle:nibBundleOrNil];

    if (!self) {
        return nil;
    }

    _device = MTLCreateSystemDefaultDevice();

    if (!_device) {
        NSLog(@"[ModMenu] Metal device unavailable");
        return nil;
    }

    _commandQueue = [_device newCommandQueue];

    if (!_commandQueue) {
        NSLog(@"[ModMenu] Command queue unavailable");
        return nil;
    }

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();

    ImGuiIO &io = ImGui::GetIO();
    io.IniFilename = nullptr;

    ImGui::StyleColorsDark();

    // Optional custom font.
    // Remove this block if Honkai.h does not provide these symbols.
    ImFont *customFont =
        io.Fonts->AddFontFromMemoryCompressedTTF(
            Honkai_compressed_data,
            Honkai_compressed_size,
            20.0f,
            nullptr,
            io.Fonts->GetGlyphRangesDefault()
        );

    if (!customFont) {
        NSLog(@"[ModMenu] Custom font unavailable; using default");
    }

    if (!ImGui_ImplMetal_Init(_device)) {
        NSLog(@"[ModMenu] ImGui Metal initialization failed");
        ImGui::DestroyContext();
        return nil;
    }

    NSLog(@"[ModMenu] ImGui initialized");
    return self;
}

#pragma mark - View

- (void)loadView
{
    MTKView *metalView =
        [[MTKView alloc] initWithFrame:UIScreen.mainScreen.bounds
                                device:self.device];

    metalView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;

    metalView.backgroundColor = UIColor.clearColor;
    metalView.opaque = NO;
    metalView.clearColor = MTLClearColorMake(0, 0, 0, 0);
    metalView.framebufferOnly = YES;
    metalView.paused = NO;
    metalView.enableSetNeedsDisplay = NO;
    metalView.preferredFramesPerSecond = 60;
    metalView.userInteractionEnabled = YES;

    self.view = metalView;
}

- (MTKView *)mtkView
{
    return (MTKView *)self.view;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    MTKView *view = self.mtkView;
    view.device = self.device;
    view.delegate = self;

    UITapGestureRecognizer *gesture =
        [[UITapGestureRecognizer alloc]
            initWithTarget:self
            action:@selector(handleMenuToggle:)];

    gesture.numberOfTapsRequired = 2;
    gesture.numberOfTouchesRequired = 3;
    gesture.cancelsTouchesInView = NO;

    [view addGestureRecognizer:gesture];
    self.toggleGesture = gesture;

    NSLog(@"[ModMenu] Three-finger double-tap installed");
}

+ (void)showChange:(BOOL)open
{
    MenDeal = open;
}

- (void)handleMenuToggle:(UITapGestureRecognizer *)gesture
{
    if (gesture.state != UIGestureRecognizerStateRecognized) {
        return;
    }

    MenDeal = !MenDeal;

    // Keep the view interactive so the menu can be reopened.
    self.mtkView.userInteractionEnabled = YES;

    NSLog(@"[ModMenu] Menu: %@",
          MenDeal ? @"ON" : @"OFF");
}

#pragma mark - ImGui Touch Input

- (void)updateIOWithTouchEvent:(UIEvent *)event
{
    ImGuiIO &io = ImGui::GetIO();

    UITouch *touch = event.allTouches.anyObject;

    if (touch) {
        CGPoint point = [touch locationInView:self.mtkView];

        io.MousePos = ImVec2(
            (float)point.x,
            (float)point.y
        );
    }

    bool pressed = false;

    for (UITouch *item in event.allTouches) {
        if (item.phase != UITouchPhaseEnded &&
            item.phase != UITouchPhaseCancelled) {
            pressed = true;
            break;
        }
    }

    io.MouseDown[0] = pressed;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    [self updateIOWithTouchEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    [self updateIOWithTouchEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    [self updateIOWithTouchEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches
               withEvent:(UIEvent *)event
{
    [self updateIOWithTouchEvent:event];
}

#pragma mark - Metal Rendering

- (void)drawInMTKView:(MTKView *)view
{
    @autoreleasepool {
        if (!self.device || !self.commandQueue) {
            return;
        }

        MTLRenderPassDescriptor *pass =
            view.currentRenderPassDescriptor;

        id<CAMetalDrawable> drawable =
            view.currentDrawable;

        if (!pass || !drawable) {
            return;
        }

        id<MTLCommandBuffer> commandBuffer =
            [self.commandQueue commandBuffer];

        if (!commandBuffer) {
            return;
        }

        id<MTLRenderCommandEncoder> encoder =
            [commandBuffer renderCommandEncoderWithDescriptor:pass];

        if (!encoder) {
            return;
        }

        ImGuiIO &io = ImGui::GetIO();

        io.DisplaySize = ImVec2(
            (float)view.bounds.size.width,
            (float)view.bounds.size.height
        );

        CGFloat scale =
            view.window.screen.scale ?: UIScreen.mainScreen.scale;

        io.DisplayFramebufferScale =
            ImVec2((float)scale, (float)scale);

        io.DeltaTime =
            1.0f / (float)(view.preferredFramesPerSecond ?: 60);

        ImGui_ImplMetal_NewFrame(pass);
        ImGui::NewFrame();

        // UI test controls.
        static bool showBoxes = false;
        static bool showHealth = false;
        static bool showDistance = false;
        static bool showSkeleton = false;

        static bool showAimCircle = false;
        static float aimFov = 80.0f;
        static float aimSmoothness = 5.0f;

        static bool showMovementTab = true;
        static bool showMiscTab = true;

        ImDrawList *drawList =
            ImGui::GetBackgroundDrawList();

        const float screenWidth =
            (float)view.bounds.size.width;

        const float screenHeight =
            (float)view.bounds.size.height;

        // Visual-only FOV circle for rendering validation.
        if (showAimCircle) {
            drawList->AddCircle(
                ImVec2(screenWidth * 0.5f,
                       screenHeight * 0.5f),
                aimFov,
                IM_COL32(255, 255, 255, 180),
                64,
                2.0f
            );
        }

        if (MenDeal) {
            ImGui::SetNextWindowSize(
                ImVec2(420.0f, 400.0f),
                ImGuiCond_FirstUseEver
            );

            ImGui::SetNextWindowPos(
                ImVec2(
                    (screenWidth - 420.0f) * 0.5f,
                    (screenHeight - 400.0f) * 0.5f
                ),
                ImGuiCond_FirstUseEver
            );

            ImGui::PushStyleColor(
                ImGuiCol_TitleBgActive,
                ImVec4(0.65f, 0.08f, 0.08f, 1.0f)
            );

            ImGui::PushStyleVar(
                ImGuiStyleVar_WindowRounding,
                8.0f
            );

            ImGui::Begin(
                "Metal UI Test",
                &MenDeal,
                ImGuiWindowFlags_NoCollapse
            );

            ImGui::Text(
                "FPS: %.1f",
                io.Framerate
            );

            ImGui::Separator();

            if (ImGui::BeginTabBar("MainTabs")) {

                if (ImGui::BeginTabItem("ESP")) {
                    ImGui::Checkbox(
                        "Player Boxes (test)",
                        &showBoxes
                    );

                    ImGui::Checkbox(
                        "Health Bars (test)",
                        &showHealth
                    );

                    ImGui::Checkbox(
                        "Distance Labels (test)",
                        &showDistance
                    );

                    ImGui::Checkbox(
                        "Skeleton (test)",
                        &showSkeleton
                    );

                    ImGui::EndTabItem();
                }

                if (ImGui::BeginTabItem("Aim")) {
                    ImGui::Checkbox(
                        "Show FOV Circle",
                        &showAimCircle
                    );

                    ImGui::SliderFloat(
                        "FOV",
                        &aimFov,
                        10.0f,
                        300.0f
                    );

                    ImGui::SliderFloat(
                        "Smoothness",
                        &aimSmoothness,
                        1.0f,
                        20.0f
                    );

                    ImGui::TextWrapped(
                        "Visual controls only. "
                        "No game input is modified."
                    );

                    ImGui::EndTabItem();
                }

                if (ImGui::BeginTabItem("Move")) {
                    ImGui::Checkbox(
                        "Show movement tab",
                        &showMovementTab
                    );

                    ImGui::TextWrapped(
                        "Movement patch controls are "
                        "not connected in this test build."
                    );

                    ImGui::EndTabItem();
                }

                if (ImGui::BeginTabItem("Misc")) {
                    ImGui::Checkbox(
                        "Show miscellaneous tab",
                        &showMiscTab
                    );

                    ImGui::Text(
                        "Metal overlay diagnostic"
                    );

                    ImGui::EndTabItem();
                }

                ImGui::EndTabBar();
            }

            ImGui::Separator();

            if (ImGui::Button("Hide Menu")) {
                MenDeal = false;
            }

            ImGui::SameLine();

            if (ImGui::Button("Reset Visuals")) {
                showBoxes = false;
                showHealth = false;
                showDistance = false;
                showSkeleton = false;
                showAimCircle = false;
                aimFov = 80.0f;
                aimSmoothness = 5.0f;
            }

            ImGui::End();

            ImGui::PopStyleVar();
            ImGui::PopStyleColor(1);
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
}

- (void)mtkView:(MTKView *)view
drawableSizeWillChange:(CGSize)size
{
    NSLog(
        @"[ModMenu] Drawable size: %.0f x %.0f",
        size.width,
        size.height
    );
}

#pragma mark - Cleanup

- (void)dealloc
{
    if (ImGui::GetCurrentContext()) {
        ImGui_ImplMetal_Shutdown();
        ImGui::DestroyContext();
    }
}

@end
