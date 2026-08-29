import Foundation

#if canImport(SceneKit)
import Combine
import SceneKit

#if os(iOS)
import UIKit
private typealias BodyTrendPlatformColor = UIColor
private typealias BodyTrendPlatformImage = UIImage
private typealias BodyTrendPlatformPath = UIBezierPath
#elseif os(macOS)
import AppKit
private typealias BodyTrendPlatformColor = NSColor
private typealias BodyTrendPlatformImage = NSImage
private typealias BodyTrendPlatformPath = NSBezierPath
#endif

struct BodyAvatarSceneInput: Equatable {
    let snapshot: InBodySnapshot?
    let previousSnapshot: InBodySnapshot?
    let style: AvatarStyle
    let imageData: Data?
}

final class BodyAvatarSceneController: ObservableObject {
    @Published private(set) var scene: SCNScene
    private var input: BodyAvatarSceneInput

    init(input: BodyAvatarSceneInput) {
        self.input = input
        scene = BodyAvatarSceneRenderer.makeScene(
            snapshot: input.snapshot,
            previousSnapshot: input.previousSnapshot,
            style: input.style,
            imageData: input.imageData
        )
    }

    func update(input newInput: BodyAvatarSceneInput) {
        guard newInput != input else { return }
        input = newInput
        scene = BodyAvatarSceneRenderer.makeScene(
            snapshot: newInput.snapshot,
            previousSnapshot: newInput.previousSnapshot,
            style: newInput.style,
            imageData: newInput.imageData
        )
    }
}

/// SceneKit-only renderer for the body trend avatar. The avatar is an
/// illustrative, parameterized character rather than a scan or a medical
/// reconstruction. Keeping all geometry here leaves the SwiftUI view focused
/// on presentation and keeps the trend domain independent from SceneKit.
enum BodyAvatarSceneRenderer {
    static func makeScene(
        snapshot: InBodySnapshot?,
        previousSnapshot: InBodySnapshot?,
        style: AvatarStyle,
        imageData: Data?
    ) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = color("FFF7FB")
        scene.lightingEnvironment.contents = color("FFF9FC")
        scene.lightingEnvironment.intensity = 0.42
        scene.fogColor = color("FFF7FB")
        scene.fogStartDistance = 9
        scene.fogEndDistance = 20

        let parameters = snapshot?.avatarParameters(relativeTo: previousSnapshot) ?? .neutral
        let width = Float(clamp(parameters.waistScale, lower: 0.82, upper: 1.20))
        let depth = Float(clamp(parameters.torsoScale, lower: 0.82, upper: 1.16))
        let height = Float(clamp(parameters.limbScale, lower: 0.92, upper: 1.10))

        let avatarRoot = SCNNode()
        switch style {
        case .helloKitty:
            addHelloKitty(to: avatarRoot, width: width, depth: depth, height: height, mood: snapshot?.mood)
        case .human:
            addHuman(to: avatarRoot, width: width, depth: depth, height: height, mood: snapshot?.mood)
        case .cat:
            addAnimal(to: avatarRoot, kind: .cat, width: width, depth: depth, height: height, mood: snapshot?.mood)
        case .dog:
            addAnimal(to: avatarRoot, kind: .dog, width: width, depth: depth, height: height, mood: snapshot?.mood)
        case .custom:
            if let imageData, let image = BodyTrendPlatformImage(data: imageData) {
                addPhoto(to: avatarRoot, image: image, width: width, height: height)
            } else {
                addHuman(to: avatarRoot, width: width, depth: depth, height: height, mood: snapshot?.mood)
            }
        }

        // Kitty uses a clean, front-facing composition so the ears, bow, and
        // feet remain visible at once. Other legacy avatars keep their gentle
        // angled presentation.
        avatarRoot.position = SCNVector3(0, style == .helloKitty ? 0.015 : 0.055, 0)
        setYRotation(on: avatarRoot, value: style == .helloKitty ? 0 : -0.10)
        scene.rootNode.addChildNode(avatarRoot)

        if style == .helloKitty {
            addKittyBackdrop(to: scene)
            addKittyGround(to: scene)
        } else {
            addBackdrop(to: scene, mood: snapshot?.mood)
            addStage(to: scene, mood: snapshot?.mood)
        }
        addCamera(to: scene, fullBody: style == .helloKitty)
        addLights(to: scene, mood: snapshot?.mood, kitty: style == .helloKitty)

        let bob = SCNAction.sequence([
            SCNAction.moveBy(x: 0, y: 0.014, z: 0, duration: 2.4),
            SCNAction.moveBy(x: 0, y: -0.014, z: 0, duration: 2.4)
        ])
        bob.timingMode = .easeInEaseOut
        avatarRoot.runAction(.repeatForever(bob), forKey: "gentle-bob")
        return scene
    }

    // MARK: - Scene dressing

    private static func addBackdrop(to scene: SCNScene, mood: MoodLevel?) {
        let paper = roundedBox(width: 5.2, height: 3.75, depth: 0.08, radius: 0.34,
                               material: material(color("FFFDFE"), roughness: 0.92, metalness: 0, clearCoat: 0))
        let paperNode = SCNNode(geometry: paper)
        paperNode.position = SCNVector3(0, 1.33, -1.68)
        scene.rootNode.addChildNode(paperNode)

        // A quiet oval wash separates the character from the paper without
        // introducing a busy illustration behind it.
        let halo = SCNSphere(radius: 1)
        halo.segmentCount = 64
        halo.firstMaterial = material(ribbonColor(mood, alpha: 0.25), roughness: 0.98, metalness: 0, clearCoat: 0)
        halo.firstMaterial?.transparency = 0.72
        halo.firstMaterial?.writesToDepthBuffer = false
        let haloNode = SCNNode(geometry: halo)
        haloNode.scale = SCNVector3(1.53, 1.12, 0.035)
        haloNode.position = SCNVector3(0, 1.34, -1.48)
        scene.rootNode.addChildNode(haloNode)

        // Two tiny paper tabs provide a designed frame while leaving generous
        // negative space around the avatar.
        let tabMaterial = material(color("FFFFFF", alpha: 0.80), roughness: 0.78, metalness: 0, clearCoat: 0.04)
        addRoundedBox(to: scene.rootNode, width: 0.48, height: 0.09, depth: 0.025,
                      radius: 0.035, position: SCNVector3(-1.76, 2.68, -1.57),
                      material: tabMaterial, rotation: -0.12)
        addRoundedBox(to: scene.rootNode, width: 0.36, height: 0.08, depth: 0.025,
                      radius: 0.03, position: SCNVector3(1.77, 0.32, -1.57),
                      material: tabMaterial, rotation: 0.16)
    }

    /// The Kitty composition intentionally has no paper tabs, halo, or front
    /// decoration. A quiet wall keeps the silhouette readable and leaves the
    /// complete character unobstructed.
    private static func addKittyBackdrop(to scene: SCNScene) {
        let wall = roundedBox(width: 5.6, height: 4.7, depth: 0.06, radius: 0.18,
                              material: material(color("FFFDFE"), roughness: 0.96, metalness: 0, clearCoat: 0))
        let wallNode = SCNNode(geometry: wall)
        wallNode.position = SCNVector3(0, 1.55, -1.85)
        scene.rootNode.addChildNode(wallNode)
    }

    /// A soft contact shadow grounds Kitty without a plinth crossing in front
    /// of the feet. The shadow is depth-disabled so it can never occlude the
    /// avatar while the user rotates the SceneView.
    private static func addKittyGround(to scene: SCNScene) {
        let floor = SCNFloor()
        floor.reflectivity = 0.04
        floor.firstMaterial = material(color("FFF4F8"), roughness: 0.98, metalness: 0, clearCoat: 0)
        let floorNode = SCNNode(geometry: floor)
        floorNode.position.y = -0.07
        scene.rootNode.addChildNode(floorNode)

        let shadow = SCNSphere(radius: 1)
        shadow.segmentCount = 64
        shadow.firstMaterial = material(color("D99AB0", alpha: 0.16), roughness: 1, metalness: 0, clearCoat: 0)
        shadow.firstMaterial?.writesToDepthBuffer = false
        shadow.firstMaterial?.readsFromDepthBuffer = false
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.scale = SCNVector3(0.72, 0.018, 0.28)
        shadowNode.position = SCNVector3(0, -0.052, 0.08)
        scene.rootNode.addChildNode(shadowNode)
    }

    private static func addStage(to scene: SCNScene, mood: MoodLevel?) {
        let floor = SCNFloor()
        floor.reflectivity = 0.10
        floor.firstMaterial = material(color("F2ECF7"), roughness: 0.90, metalness: 0, clearCoat: 0)
        let floorNode = SCNNode(geometry: floor)
        floorNode.position.y = -0.31
        floorNode.opacity = 0.94
        scene.rootNode.addChildNode(floorNode)

        let platform = SCNCylinder(radius: 1.30, height: 0.10)
        platform.radialSegmentCount = 96
        platform.firstMaterial = material(color("FFFFFF"), roughness: 0.50, metalness: 0.03, clearCoat: 0.20)
        let platformNode = SCNNode(geometry: platform)
        platformNode.position.y = -0.255
        scene.rootNode.addChildNode(platformNode)

        let inset = SCNCylinder(radius: 1.16, height: 0.022)
        inset.radialSegmentCount = 96
        inset.firstMaterial = material(ribbonColor(mood, alpha: 0.42), roughness: 0.64, metalness: 0.01, clearCoat: 0.10)
        let insetNode = SCNNode(geometry: inset)
        insetNode.position.y = -0.195
        scene.rootNode.addChildNode(insetNode)

        let rim = SCNTorus(ringRadius: 1.09, pipeRadius: 0.018)
        rim.ringSegmentCount = 96
        rim.pipeSegmentCount = 14
        rim.firstMaterial = material(ribbonColor(mood), roughness: 0.42, metalness: 0.04, clearCoat: 0.22)
        let rimNode = SCNNode(geometry: rim)
        rimNode.position.y = -0.175
        scene.rootNode.addChildNode(rimNode)
    }

    private static func addCamera(to scene: SCNScene, fullBody: Bool = false) {
        let target = SCNNode()
        target.position = SCNVector3(0, fullBody ? 1.23 : 1.03, 0)
        scene.rootNode.addChildNode(target)

        let camera = SCNCamera()
        camera.fieldOfView = fullBody ? 28 : 34
        camera.zNear = 0.05
        camera.zFar = 50
        camera.automaticallyAdjustsZRange = true
        camera.wantsHDR = true
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, fullBody ? 1.25 : 1.13, fullBody ? 5.55 : 4.85)
        cameraNode.constraints = [SCNLookAtConstraint(target: target)]
        scene.rootNode.addChildNode(cameraNode)
    }

    private static func addLights(to scene: SCNScene, mood: MoodLevel?, kitty: Bool = false) {
        let key = SCNLight()
        key.type = .area
        key.intensity = kitty ? 820 : 680
        key.color = color("FFFDFB")
        key.castsShadow = true
        key.shadowRadius = 10
        key.shadowColor = color("5D4A70", alpha: 0.16)
        #if os(macOS)
        key.shadowMapSize = CGSize(width: 512, height: 512)
        key.shadowSampleCount = 8
        #endif
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(2.8, 3.5, 4.2)
        keyNode.eulerAngles = SCNVector3(-0.52, 0.44, 0)
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .area
        fill.intensity = kitty ? 430 : 330
        fill.color = kitty ? color("FFEAF2") : color("EAE2FF")
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(-2.4, 2.0, 2.5)
        scene.rootNode.addChildNode(fillNode)

        let rim = SCNLight()
        rim.type = .omni
        rim.intensity = kitty ? 220 : 300
        rim.color = kitty ? color("F7B5C8") : ribbonColor(mood)
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(0.8, 2.7, -2.4)
        scene.rootNode.addChildNode(rimNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 95
        ambient.color = color("FFF8FF")
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
    }

    // MARK: - Hello Kitty character

    /// A small, original SceneKit interpretation of Hello Kitty's visual
    /// signature: white rounded head and body, red bow and dress, yellow nose,
    /// oval eyes, and whiskers. It is built as one centered full-body subject
    /// so body-trend changes can still scale the silhouette without cropping
    /// the ears or feet.
    private static func addHelloKitty(to root: SCNNode, width: Float, depth: Float,
                                      height: Float, mood: MoodLevel?) {
        let w = CGFloat(width)
        let d = CGFloat(depth)
        let h = CGFloat(height)
        let white = material(color("FFFDFB"), roughness: 0.48, metalness: 0, clearCoat: 0.22)
        let whiteShadow = material(color("F3EAF0"), roughness: 0.64, metalness: 0, clearCoat: 0.10)
        let red = material(color("EF5C78"), roughness: 0.42, metalness: 0.01, clearCoat: 0.20)
        let redDeep = material(color("C83E61"), roughness: 0.48, metalness: 0.01, clearCoat: 0.16)
        let pink = material(color("F6B4C8"), roughness: 0.58, metalness: 0, clearCoat: 0.10)
        let black = material(color("2D2630"), roughness: 0.35, metalness: 0, clearCoat: 0.20)
        let yellow = material(color("F6C85F"), roughness: 0.40, metalness: 0.01, clearCoat: 0.18)

        // Feet and legs are separated just enough to read as a complete body.
        for side: Float in [-1, 1] {
            addRoundedBox(to: root, width: 0.22 * w, height: 0.38 * h, depth: 0.22 * d,
                          radius: 0.10, position: SCNVector3(side * 0.18 * width, 0.17, 0.01), material: white)
            addRoundedBox(to: root, width: 0.34 * w, height: 0.15, depth: 0.34 * d,
                          radius: 0.07, position: SCNVector3(side * 0.19 * width, 0.015, 0.10 * depth), material: red)
        }

        // Rounded body plus a single tapered dress keeps the silhouette soft,
        // with no foreground prop crossing the legs.
        let body = roundedBox(width: 0.82 * w, height: 0.82 * h, depth: 0.54 * d,
                              radius: 0.24, material: white)
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.77, 0)
        root.addChildNode(bodyNode)

        let dress = extrudedShape(path: dressPath(width: 0.98 * w, height: 0.88 * h), depth: 0.56 * d,
                                  material: red, chamfer: 0.055)
        let dressNode = SCNNode(geometry: dress)
        dressNode.position = SCNVector3(0, 0.69, -Float(0.28 * d))
        root.addChildNode(dressNode)

        // White bib and red straps add the familiar pinafore detail without
        // covering the face or breaking the full-body read.
        addRoundedBox(to: root, width: 0.48 * w, height: 0.38 * h, depth: 0.075,
                      radius: 0.11, position: SCNVector3(0, 0.98, 0.30 * depth), material: white)
        for side: Float in [-1, 1] {
            addRoundedBox(to: root, width: 0.075 * w, height: 0.34 * h, depth: 0.08,
                          radius: 0.035, position: SCNVector3(side * 0.22 * width, 1.06, 0.30 * depth), material: redDeep,
                          rotation: side * 0.08)
        }
        let button = SCNSphere(radius: 0.045)
        button.segmentCount = 24
        button.firstMaterial = yellow
        let buttonNode = SCNNode(geometry: button)
        buttonNode.position = SCNVector3(0, 0.98, 0.35 * depth)
        root.addChildNode(buttonNode)

        // Arms stay outside the dress so the silhouette remains legible.
        addLimb(to: root, position: SCNVector3(-0.48 * width, 0.88, 0.01), radius: 0.105,
                length: 0.48 * height, material: white, rotation: -0.36)
        addLimb(to: root, position: SCNVector3(0.48 * width, 0.88, 0.01), radius: 0.105,
                length: 0.48 * height, material: white, rotation: 0.36)
        addRoundedBox(to: root, width: 0.18 * w, height: 0.16, depth: 0.18 * d,
                      radius: 0.075, position: SCNVector3(-0.57 * width, 0.67, 0.08), material: whiteShadow)
        addRoundedBox(to: root, width: 0.18 * w, height: 0.16, depth: 0.18 * d,
                      radius: 0.075, position: SCNVector3(0.57 * width, 0.67, 0.08), material: whiteShadow)

        // Head and ears are intentionally larger than the body, but both ears
        // remain inside the camera's full-body framing.
        let head = roundedBox(width: 1.06 * w, height: 0.86 * h, depth: 0.66 * d,
                              radius: 0.28, material: white)
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 1.84, 0.025)
        root.addChildNode(headNode)
        addCatEar(to: root, x: -0.43 * width, y: 2.22, z: -0.04,
                  fur: white, inner: pink, rotation: -0.10)
        addCatEar(to: root, x: 0.43 * width, y: 2.22, z: -0.04,
                  fur: white, inner: pink, rotation: 0.10)

        // Hello Kitty's bow sits beside the viewer-right ear in a front view.
        addBow(to: root, position: SCNVector3(0.48 * width, 2.27, 0.34 * depth),
               material: red, scale: 1.10)
        addRoundedBox(to: root, width: 0.11, height: 0.11, depth: 0.085, radius: 0.045,
                      position: SCNVector3(0.48 * width, 2.27, 0.405 * depth), material: redDeep)

        addHelloKittyFace(to: root, width: width, depth: depth, eyes: black, nose: yellow,
                          whiskers: black, mood: mood)
    }

    private static func addHelloKittyFace(to root: SCNNode, width: Float, depth: Float,
                                          eyes: SCNMaterial, nose: SCNMaterial,
                                          whiskers: SCNMaterial, mood: MoodLevel?) {
        // The face uses simple high-contrast shapes rather than a mouth; the
        // missing mouth is part of the character's recognizable expression.
        for side: Float in [-1, 1] {
            addRoundedBox(to: root, width: 0.105, height: 0.22, depth: 0.055,
                          radius: 0.045, position: SCNVector3(side * 0.22 * width, 1.91, 0.385 * depth), material: eyes)
        }
        let noseGeometry = roundedBox(width: 0.13, height: 0.095, depth: 0.075,
                                      radius: 0.04, material: nose)
        let noseNode = SCNNode(geometry: noseGeometry)
        noseNode.position = SCNVector3(0, 1.76, 0.41 * depth)
        root.addChildNode(noseNode)

        // Three delicate whiskers on each side. They sit on the face plane,
        // never in front of the body, so camera rotation cannot make them read
        // as an obstruction.
        let sideSign: [Float] = [-1, 1]
        for side in sideSign {
            let outward: Float = side < 0 ? -1 : 1
            let rows: [(Float, Float)] = [(1.86, 0.12), (1.76, 0.02), (1.66, -0.10)]
            for (y, tilt) in rows {
                let whisker = SCNCapsule(capRadius: 0.011, height: 0.28)
                whisker.radialSegmentCount = 16
                whisker.firstMaterial = whiskers
                let node = SCNNode(geometry: whisker)
                node.position = SCNVector3(side * 0.39 * width, y, 0.395 * depth)
                setZRotation(on: node, value: outward * (Float.pi / 2 + tilt))
                root.addChildNode(node)
            }
        }

        // A tiny pink cheek wash responds to mood without adding facial text
        // or covering the eyes.
        if mood == .good || mood == .excellent {
            let cheek = material(color("F39AB8", alpha: 0.42), roughness: 0.64, metalness: 0, clearCoat: 0.04)
            for side: Float in [-1, 1] {
                addRoundedBox(to: root, width: 0.13, height: 0.045, depth: 0.025,
                              radius: 0.02, position: SCNVector3(side * 0.36 * width, 1.73, 0.405 * depth), material: cheek,
                              rotation: side * 0.08)
            }
        }
    }

    // MARK: - Human character

    private static func addHuman(to root: SCNNode, width: Float, depth: Float, height: Float, mood: MoodLevel?) {
        let w = CGFloat(width)
        let d = CGFloat(depth)
        let h = CGFloat(height)
        let skin = material(color("FFE5D7"), roughness: 0.70, metalness: 0, clearCoat: 0.05)
        let hair = material(color("725B91"), roughness: 0.56, metalness: 0.01, clearCoat: 0.14)
        let hairLight = material(color("8D76AD"), roughness: 0.60, metalness: 0.01, clearCoat: 0.12)
        let outfit = material(moodColor(mood), roughness: 0.54, metalness: 0.01, clearCoat: 0.18)
        let outfitLight = material(color("FFF3FA"), roughness: 0.62, metalness: 0, clearCoat: 0.10)
        let accent = material(color("F4A9C4"), roughness: 0.45, metalness: 0.01, clearCoat: 0.24)

        // Shoes and legs establish a relaxed, slightly pigeon-toed stance.
        addRoundedBox(to: root, width: 0.18 * w, height: 0.42 * h, depth: 0.18 * d,
                      radius: 0.085, position: SCNVector3(-0.14 * width, 0.16, 0), material: skin)
        addRoundedBox(to: root, width: 0.18 * w, height: 0.42 * h, depth: 0.18 * d,
                      radius: 0.085, position: SCNVector3(0.14 * width, 0.16, 0), material: skin)
        addRoundedBox(to: root, width: 0.25 * w, height: 0.13, depth: 0.34 * d,
                      radius: 0.065, position: SCNVector3(-0.16 * width, -0.075, 0.09), material: accent)
        addRoundedBox(to: root, width: 0.25 * w, height: 0.13, depth: 0.34 * d,
                      radius: 0.065, position: SCNVector3(0.16 * width, -0.075, 0.09), material: accent)

        // A single tapered silhouette reads as a garment, avoiding the stack
        // of disconnected primitive spheres that made the old avatar rigid.
        let dress = extrudedShape(path: dressPath(width: 0.88 * w, height: 1.08 * h), depth: 0.53 * d,
                                  material: outfit, chamfer: 0.045)
        let dressNode = SCNNode(geometry: dress)
        dressNode.position = SCNVector3(0, 0.77, -Float(0.265 * d))
        root.addChildNode(dressNode)

        addRoundedBox(to: root, width: 0.48 * w, height: 0.42 * h, depth: 0.13 * d,
                      radius: 0.13, position: SCNVector3(0, 1.075, 0.285 * depth), material: outfitLight)
        addRoundedBox(to: root, width: 0.64 * w, height: 0.055, depth: 0.15 * d,
                      radius: 0.025, position: SCNVector3(0, 0.88, 0.30 * depth), material: accent)
        addRoundedBox(to: root, width: 0.70 * w, height: 0.055, depth: 0.14 * d,
                      radius: 0.025, position: SCNVector3(0, 0.38, 0.30 * depth), material: outfitLight)

        // Soft sleeves and hands sit behind the bib so the pose remains clear.
        addLimb(to: root, position: SCNVector3(-0.43 * width, 1.07, 0.02), radius: 0.095,
                length: 0.46 * height, material: outfit, rotation: -0.18)
        addLimb(to: root, position: SCNVector3(0.43 * width, 1.07, 0.02), radius: 0.095,
                length: 0.46 * height, material: outfit, rotation: 0.18)
        addRoundedBox(to: root, width: 0.17 * w, height: 0.15, depth: 0.18 * d,
                      radius: 0.075, position: SCNVector3(-0.48 * width, 0.81, 0.08), material: skin)
        addRoundedBox(to: root, width: 0.17 * w, height: 0.15, depth: 0.18 * d,
                      radius: 0.075, position: SCNVector3(0.48 * width, 0.81, 0.08), material: skin)

        // Neck, head and back hair use a rounded-square silhouette for a
        // polished vinyl-toy feel rather than an oversized sphere.
        addRoundedBox(to: root, width: 0.16 * w, height: 0.15, depth: 0.16 * d,
                      radius: 0.06, position: SCNVector3(0, 1.35, 0), material: skin)
        let backHair = roundedBox(width: 0.98 * w, height: 0.96 * h, depth: 0.42 * d,
                                  radius: 0.26, material: hair)
        let backHairNode = SCNNode(geometry: backHair)
        backHairNode.position = SCNVector3(0, 1.73, -0.12)
        root.addChildNode(backHairNode)

        let head = roundedBox(width: 0.88 * w, height: 0.78 * h, depth: 0.62 * d,
                              radius: 0.24, material: skin)
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 1.70, 0.035)
        setZRotation(on: headNode, value: 0.018)
        root.addChildNode(headNode)

        // Layered fringe and side locks create a readable silhouette at the
        // compact size used by the trend card.
        addHairFringe(to: root, width: width, depth: depth, hair: hair, hairLight: hairLight)
        for side: Float in [-1, 1] {
            addRoundedBox(to: root, width: 0.18 * w, height: 0.40 * h, depth: 0.18 * d,
                          radius: 0.085, position: SCNVector3(side * 0.40 * width, 1.54, 0.18 * depth),
                          material: hair, rotation: -side * 0.10)
            addRoundedBox(to: root, width: 0.11 * w, height: 0.24 * h, depth: 0.10 * d,
                          radius: 0.05, position: SCNVector3(side * 0.46 * width, 1.42, 0.20 * depth),
                          material: hairLight, rotation: -side * 0.08)
        }
        addBow(to: root, position: SCNVector3(0.37 * width, 2.08, 0.18 * depth), material: accent, scale: 0.72)
        addHumanFace(to: root, y: 1.70, faceWidth: width, faceDepth: depth, mood: mood)
    }

    private static func addHairFringe(to root: SCNNode, width: Float, depth: Float,
                                      hair: SCNMaterial, hairLight: SCNMaterial) {
        let w = CGFloat(width)
        let d = CGFloat(depth)
        let fringeSpecs: [(Float, Float, Float, SCNMaterial)] = [
            (-0.27, 1.95, -0.18, hair),
            (-0.13, 2.00, -0.08, hairLight),
            (0.02, 2.01, 0.00, hair),
            (0.17, 1.98, 0.10, hairLight),
            (0.30, 1.93, 0.18, hair)
        ]
        for (x, y, angle, tint) in fringeSpecs {
            addRoundedBox(to: root, width: 0.23 * w, height: 0.28, depth: 0.13 * d,
                          radius: 0.095, position: SCNVector3(x * width, y, 0.32 * depth),
                          material: tint, rotation: angle)
        }
    }

    private static func addHumanFace(to root: SCNNode, y: Float, faceWidth: Float,
                                     faceDepth: Float, mood: MoodLevel?) {
        let w = CGFloat(faceWidth)
        let eyeWhite = material(color("FFFEFC"), roughness: 0.28, metalness: 0, clearCoat: 0.28)
        let iris = material(color("5C4A78"), roughness: 0.32, metalness: 0, clearCoat: 0.38)
        let irisGlow = material(color("9D8AC5"), roughness: 0.36, metalness: 0, clearCoat: 0.28)
        let cheek = material(color("F39AB8", alpha: 0.58), roughness: 0.55, metalness: 0, clearCoat: 0.04)
        let brow = material(color("6A527E"), roughness: 0.58, metalness: 0, clearCoat: 0.06)

        for side: Float in [-1, 1] {
            addRoundedBox(to: root, width: 0.205 * w, height: 0.285, depth: 0.085,
                          radius: 0.095, position: SCNVector3(side * 0.185 * faceWidth, y + 0.015, 0.345 * faceDepth), material: eyeWhite)
            addRoundedBox(to: root, width: 0.105 * w, height: 0.17, depth: 0.055,
                          radius: 0.045, position: SCNVector3(side * 0.185 * faceWidth, y + 0.005, 0.405 * faceDepth), material: iris)
            addRoundedBox(to: root, width: 0.060 * w, height: 0.10, depth: 0.032,
                          radius: 0.028, position: SCNVector3(side * 0.185 * faceWidth, y - 0.005, 0.438 * faceDepth), material: irisGlow)
            let shine = SCNSphere(radius: 0.026)
            shine.segmentCount = 24
            shine.firstMaterial = material(color("FFFFFF"), roughness: 0.12, metalness: 0, clearCoat: 0.55)
            let shineNode = SCNNode(geometry: shine)
            shineNode.position = SCNVector3(side * 0.16 * faceWidth, y + 0.068, 0.468 * faceDepth)
            root.addChildNode(shineNode)

            addRoundedBox(to: root, width: 0.13 * w, height: 0.026, depth: 0.025,
                          radius: 0.013, position: SCNVector3(side * 0.185 * faceWidth, y + 0.205, 0.36 * faceDepth), material: brow, rotation: side * 0.08)
            addRoundedBox(to: root, width: 0.17 * w, height: 0.062, depth: 0.022,
                          radius: 0.028, position: SCNVector3(side * 0.285 * faceWidth, y - 0.105, 0.365 * faceDepth), material: cheek, rotation: side * 0.08)
        }

        let nose = SCNSphere(radius: 0.034)
        nose.segmentCount = 24
        nose.firstMaterial = material(color("E69A9D"), roughness: 0.42, metalness: 0, clearCoat: 0.10)
        let noseNode = SCNNode(geometry: nose)
        noseNode.scale = SCNVector3(1.2, 0.72, 0.7)
        noseNode.position = SCNVector3(0, y - 0.075, 0.445 * faceDepth)
        root.addChildNode(noseNode)

        let mouth = roundedBox(width: 0.13, height: 0.032, depth: 0.025, radius: 0.014,
                               material: material(color("915C79"), roughness: 0.48, metalness: 0, clearCoat: 0.08))
        let mouthNode = SCNNode(geometry: mouth)
        mouthNode.position = SCNVector3(0, y - 0.155, 0.445 * faceDepth)
        mouthNode.scale = SCNVector3(1, mood == .low || mood == .veryLow ? 0.72 : 1.0, 1)
        root.addChildNode(mouthNode)
        addRoundedBox(to: root, width: 0.045, height: 0.025, depth: 0.020, radius: 0.012,
                      position: SCNVector3(0, y - 0.184, 0.448 * faceDepth), material: cheek)
    }

    // MARK: - Animal characters

    private enum AnimalKind { case cat, dog }

    private static func addAnimal(to root: SCNNode, kind: AnimalKind, width: Float, depth: Float,
                                  height: Float, mood: MoodLevel?) {
        let w = CGFloat(width)
        let d = CGFloat(depth)
        let h = CGFloat(height)
        let isCat = kind == .cat
        let fur = material(color(isCat ? "B7A7D6" : "D9B49B"), roughness: 0.74, metalness: 0, clearCoat: 0.08)
        let furLight = material(color(isCat ? "DCCFF0" : "F0D2BC"), roughness: 0.80, metalness: 0, clearCoat: 0.04)
        let innerEar = material(color(isCat ? "F0B0C8" : "E7AFA8"), roughness: 0.66, metalness: 0, clearCoat: 0.04)
        let accent = material(color(isCat ? "F39BBC" : "A7C7E7"), roughness: 0.46, metalness: 0.01, clearCoat: 0.20)

        addRoundedBox(to: root, width: 0.22 * w, height: 0.36 * h, depth: 0.20 * d,
                      radius: 0.10, position: SCNVector3(-0.23 * width, 0.15, 0.02), material: fur)
        addRoundedBox(to: root, width: 0.22 * w, height: 0.36 * h, depth: 0.20 * d,
                      radius: 0.10, position: SCNVector3(0.23 * width, 0.15, 0.02), material: fur)
        addRoundedBox(to: root, width: 0.34 * w, height: 0.14, depth: 0.31 * d,
                      radius: 0.07, position: SCNVector3(-0.25 * width, -0.055, 0.10), material: furLight)
        addRoundedBox(to: root, width: 0.34 * w, height: 0.14, depth: 0.31 * d,
                      radius: 0.07, position: SCNVector3(0.25 * width, -0.055, 0.10), material: furLight)

        let body = roundedBox(width: 0.98 * w, height: 0.68 * h, depth: 0.62 * d, radius: 0.24, material: fur)
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.72, 0)
        root.addChildNode(bodyNode)
        addRoundedBox(to: root, width: 0.47 * w, height: 0.45 * h, depth: 0.085,
                      radius: 0.19, position: SCNVector3(0, 0.72, 0.325 * depth), material: furLight)
        addRoundedBox(to: root, width: 0.62 * w, height: 0.065, depth: 0.095,
                      radius: 0.03, position: SCNVector3(0, 0.98, 0.33 * depth), material: accent)

        let head = roundedBox(width: 0.92 * w, height: 0.74 * h, depth: 0.60 * d, radius: 0.25, material: fur)
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 1.49, 0.03)
        setZRotation(on: headNode, value: isCat ? -0.025 : 0.025)
        root.addChildNode(headNode)

        if isCat {
            addCatEar(to: root, x: -0.33 * width, y: 1.90, z: 0.02, fur: fur, inner: innerEar, rotation: -0.12)
            addCatEar(to: root, x: 0.33 * width, y: 1.90, z: 0.02, fur: fur, inner: innerEar, rotation: 0.12)
        } else {
            addRoundedBox(to: root, width: 0.25 * w, height: 0.43 * h, depth: 0.18 * d,
                          radius: 0.105, position: SCNVector3(-0.43 * width, 1.55, -0.02), material: fur, rotation: -0.34)
            addRoundedBox(to: root, width: 0.25 * w, height: 0.43 * h, depth: 0.18 * d,
                          radius: 0.105, position: SCNVector3(0.43 * width, 1.55, -0.02), material: fur, rotation: 0.34)
            addRoundedBox(to: root, width: 0.12 * w, height: 0.22 * h, depth: 0.05,
                          radius: 0.055, position: SCNVector3(-0.43 * width, 1.55, 0.085), material: innerEar, rotation: -0.34)
            addRoundedBox(to: root, width: 0.12 * w, height: 0.22 * h, depth: 0.05,
                          radius: 0.055, position: SCNVector3(0.43 * width, 1.55, 0.085), material: innerEar, rotation: 0.34)
        }

        let muzzle = roundedBox(width: 0.42 * w, height: 0.22 * h, depth: 0.18, radius: 0.10, material: furLight)
        let muzzleNode = SCNNode(geometry: muzzle)
        muzzleNode.position = SCNVector3(0, 1.39, 0.34 * depth)
        root.addChildNode(muzzleNode)

        // A little scarf and charm give the animals a designed identity.
        addRoundedBox(to: root, width: 0.70 * w, height: 0.075, depth: 0.10 * d,
                      radius: 0.035, position: SCNVector3(0, 1.22, 0.22 * depth), material: accent)
        addRoundedBox(to: root, width: 0.16 * w, height: 0.14, depth: 0.045,
                      radius: 0.035, position: SCNVector3(0, 1.13, 0.29 * depth), material: innerEar)
        addAnimalTail(to: root, width: width, depth: depth, fur: fur, dog: !isCat)
        addBow(to: root, position: SCNVector3(isCat ? -0.37 * width : 0.37 * width, 1.91, 0.16 * depth), material: accent, scale: 0.58)
        addAnimalFace(to: root, y: 1.49, faceWidth: width, faceDepth: depth, kind: kind, mood: mood)
    }

    private static func addCatEar(to root: SCNNode, x: Float, y: Float, z: Float,
                                  fur: SCNMaterial, inner: SCNMaterial, rotation: Float) {
        let outer = extrudedShape(path: trianglePath(width: 0.34, height: 0.38), depth: 0.16,
                                  material: fur, chamfer: 0.035)
        let outerNode = SCNNode(geometry: outer)
        outerNode.position = SCNVector3(x, y, z)
        setZRotation(on: outerNode, value: rotation)
        root.addChildNode(outerNode)

        let innerGeometry = extrudedShape(path: trianglePath(width: 0.18, height: 0.22), depth: 0.018,
                                          material: inner, chamfer: 0.018)
        let innerNode = SCNNode(geometry: innerGeometry)
        innerNode.position = SCNVector3(x, y - 0.01, 0.085)
        setZRotation(on: innerNode, value: rotation)
        root.addChildNode(innerNode)
    }

    private static func addAnimalTail(to root: SCNNode, width: Float, depth: Float,
                                      fur: SCNMaterial, dog: Bool) {
        let sign: Float = dog ? -1 : 1
        let positions: [(Float, Float, Float)] = dog
            ? [(0.56, 0.64, -0.12), (0.70, 0.83, -0.10), (0.66, 1.02, -0.08)]
            : [(0.55, 0.65, -0.12), (0.74, 0.79, -0.10), (0.76, 0.99, -0.08)]
        for (index, item) in positions.enumerated() {
            let segment = SCNCapsule(capRadius: dog ? 0.085 : 0.075, height: dog ? 0.30 : 0.34)
            segment.radialSegmentCount = 28
            segment.firstMaterial = fur
            let node = SCNNode(geometry: segment)
            node.position = SCNVector3(sign * item.0 * width, item.1, item.2 * depth)
            setZRotation(on: node, value: sign * (index == 0 ? -0.65 : (index == 1 ? 0.35 : 0.75)))
            root.addChildNode(node)
        }
    }

    private static func addAnimalFace(to root: SCNNode, y: Float, faceWidth: Float,
                                      faceDepth: Float, kind: AnimalKind, mood: MoodLevel?) {
        let w = CGFloat(faceWidth)
        let eye = material(color("4B3D64"), roughness: 0.30, metalness: 0, clearCoat: 0.42)
        let eyeGlow = material(color("9E8BC4"), roughness: 0.36, metalness: 0, clearCoat: 0.28)
        let cheek = material(color("F39AB8", alpha: 0.52), roughness: 0.54, metalness: 0, clearCoat: 0.04)
        for side: Float in [-1, 1] {
            addRoundedBox(to: root, width: 0.13 * w, height: 0.18, depth: 0.06,
                          radius: 0.055, position: SCNVector3(side * 0.20 * faceWidth, y + 0.03, 0.36 * faceDepth), material: eye)
            addRoundedBox(to: root, width: 0.070 * w, height: 0.10, depth: 0.028,
                          radius: 0.026, position: SCNVector3(side * 0.20 * faceWidth, y + 0.02, 0.398 * faceDepth), material: eyeGlow)
            let shine = SCNSphere(radius: 0.021)
            shine.firstMaterial = material(color("FFFFFF"), roughness: 0.12, metalness: 0, clearCoat: 0.55)
            let shineNode = SCNNode(geometry: shine)
            shineNode.position = SCNVector3(side * 0.17 * faceWidth, y + 0.075, 0.43 * faceDepth)
            root.addChildNode(shineNode)
            addRoundedBox(to: root, width: 0.16 * w, height: 0.058, depth: 0.020,
                          radius: 0.027, position: SCNVector3(side * 0.30 * faceWidth, y - 0.095, 0.37 * faceDepth), material: cheek, rotation: side * 0.08)
        }

        let nose = roundedBox(width: kind == .cat ? 0.075 : 0.10, height: 0.065, depth: 0.055,
                             radius: 0.025, material: material(kind == .cat ? color("D98C9D") : color("685652"), roughness: 0.38, metalness: 0, clearCoat: 0.16))
        let noseNode = SCNNode(geometry: nose)
        noseNode.position = SCNVector3(0, y - 0.075, 0.43 * faceDepth)
        root.addChildNode(noseNode)

        let mouth = roundedBox(width: 0.12, height: 0.028, depth: 0.022, radius: 0.012,
                               material: material(color("8D5871"), roughness: 0.46, metalness: 0, clearCoat: 0.08))
        let mouthNode = SCNNode(geometry: mouth)
        mouthNode.position = SCNVector3(0, y - 0.145, 0.432 * faceDepth)
        mouthNode.scale = SCNVector3(1, mood == .low || mood == .veryLow ? 0.72 : 1, 1)
        root.addChildNode(mouthNode)
    }

    // MARK: - Custom photo avatar

    private static func addPhoto(to root: SCNNode, image: BodyTrendPlatformImage, width: Float, height: Float) {
        let cardWidth = CGFloat(1.32 * width)
        let cardHeight = CGFloat(2.16 * height)
        let backing = roundedBox(width: cardWidth + 0.16, height: cardHeight + 0.16, depth: 0.10,
                                 radius: 0.14, material: material(color("D9C8EA"), roughness: 0.58, metalness: 0.02, clearCoat: 0.18))
        let backingNode = SCNNode(geometry: backing)
        backingNode.position = SCNVector3(0, 1.08, -0.07)
        root.addChildNode(backingNode)

        let plane = SCNPlane(width: cardWidth, height: cardHeight)
        let photoMaterial = SCNMaterial()
        photoMaterial.lightingModel = .constant
        photoMaterial.diffuse.contents = image
        photoMaterial.isDoubleSided = true
        plane.firstMaterial = photoMaterial
        let photoNode = SCNNode(geometry: plane)
        photoNode.position = SCNVector3(0, 1.08, 0.015)
        setYRotation(on: photoNode, value: 0.035)
        root.addChildNode(photoNode)

        let frame = material(color("FFFDFD"), roughness: 0.40, metalness: 0.04, clearCoat: 0.24)
        let border: CGFloat = 0.048
        addRoundedBox(to: root, width: cardWidth + 0.08, height: border, depth: 0.12, radius: 0.018,
                      position: SCNVector3(0, 1.08 + Float(cardHeight / 2) + Float(border / 2), 0.045), material: frame)
        addRoundedBox(to: root, width: cardWidth + 0.08, height: border, depth: 0.12, radius: 0.018,
                      position: SCNVector3(0, 1.08 - Float(cardHeight / 2) - Float(border / 2), 0.045), material: frame)
        addRoundedBox(to: root, width: border, height: cardHeight + 0.08, depth: 0.12, radius: 0.018,
                      position: SCNVector3(-Float(cardWidth / 2) - Float(border / 2), 1.08, 0.045), material: frame)
        addRoundedBox(to: root, width: border, height: cardHeight + 0.08, depth: 0.12, radius: 0.018,
                      position: SCNVector3(Float(cardWidth / 2) + Float(border / 2), 1.08, 0.045), material: frame)
    }

    // MARK: - Geometry helpers

    private static func roundedBox(width: CGFloat, height: CGFloat, depth: CGFloat,
                                  radius: CGFloat, material: SCNMaterial) -> SCNBox {
        let geometry = SCNBox(width: width, height: height, length: depth, chamferRadius: min(radius, min(width, min(height, depth)) / 2))
        geometry.widthSegmentCount = 4
        geometry.heightSegmentCount = 4
        geometry.lengthSegmentCount = 4
        geometry.firstMaterial = material
        return geometry
    }

    @discardableResult
    private static func addRoundedBox(to root: SCNNode, width: CGFloat, height: CGFloat, depth: CGFloat,
                                      radius: CGFloat, position: SCNVector3, material: SCNMaterial,
                                      rotation: Float = 0) -> SCNNode {
        let node = SCNNode(geometry: roundedBox(width: width, height: height, depth: depth, radius: radius, material: material))
        node.position = position
        if rotation != 0 { setZRotation(on: node, value: rotation) }
        root.addChildNode(node)
        return node
    }

    private static func extrudedShape(path: BodyTrendPlatformPath, depth: CGFloat, material: SCNMaterial, chamfer: CGFloat) -> SCNShape {
        let geometry = SCNShape(path: path, extrusionDepth: depth)
        geometry.chamferRadius = chamfer
        geometry.firstMaterial = material
        return geometry
    }

    private static func addLimb(to root: SCNNode, position: SCNVector3, radius: CGFloat,
                                length: Float, material: SCNMaterial, rotation: Float) {
        let geometry = SCNCapsule(capRadius: radius, height: CGFloat(length))
        geometry.radialSegmentCount = 36
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.position = position
        setZRotation(on: node, value: rotation)
        root.addChildNode(node)
    }

    private static func addBow(to root: SCNNode, position: SCNVector3, material: SCNMaterial, scale: Float) {
        let s = CGFloat(scale)
        addRoundedBox(to: root, width: 0.22 * s, height: 0.15 * s, depth: 0.10 * s, radius: 0.07 * s,
                      position: offsetX(position, by: -0.12 * scale), material: material, rotation: -0.25)
        addRoundedBox(to: root, width: 0.22 * s, height: 0.15 * s, depth: 0.10 * s, radius: 0.07 * s,
                      position: offsetX(position, by: 0.12 * scale), material: material, rotation: 0.25)
        let center = SCNSphere(radius: CGFloat(0.075 * scale))
        center.segmentCount = 28
        center.firstMaterial = material
        let centerNode = SCNNode(geometry: center)
        centerNode.position = position
        root.addChildNode(centerNode)
    }

    private static func offsetX(_ position: SCNVector3, by value: Float) -> SCNVector3 {
        #if os(macOS)
        return SCNVector3(position.x + CGFloat(value), position.y, position.z)
        #else
        return SCNVector3(position.x + value, position.y, position.z)
        #endif
    }

    private static func dressPath(width: CGFloat, height: CGFloat) -> BodyTrendPlatformPath {
        let half = width / 2
        let top = height * 0.48
        let bottom = -height * 0.52
        #if os(iOS)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -half * 0.52, y: top))
        path.addCurve(to: CGPoint(x: half * 0.52, y: top), controlPoint1: CGPoint(x: -half * 0.25, y: top + 0.04), controlPoint2: CGPoint(x: half * 0.25, y: top + 0.04))
        path.addCurve(to: CGPoint(x: half, y: bottom), controlPoint1: CGPoint(x: half * 0.70, y: top - 0.28), controlPoint2: CGPoint(x: half * 0.94, y: bottom + 0.18))
        path.addCurve(to: CGPoint(x: -half, y: bottom), controlPoint1: CGPoint(x: -half * 0.94, y: bottom + 0.18), controlPoint2: CGPoint(x: -half * 0.70, y: top - 0.28))
        path.close()
        return path
        #elseif os(macOS)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: -half * 0.52, y: top))
        path.curve(to: NSPoint(x: half * 0.52, y: top), controlPoint1: NSPoint(x: -half * 0.25, y: top + 0.04), controlPoint2: NSPoint(x: half * 0.25, y: top + 0.04))
        path.curve(to: NSPoint(x: half, y: bottom), controlPoint1: NSPoint(x: half * 0.70, y: top - 0.28), controlPoint2: NSPoint(x: half * 0.94, y: bottom + 0.18))
        path.curve(to: NSPoint(x: -half, y: bottom), controlPoint1: NSPoint(x: -half * 0.94, y: bottom + 0.18), controlPoint2: NSPoint(x: -half * 0.70, y: top - 0.28))
        path.close()
        return path
        #else
        return BodyTrendPlatformPath()
        #endif
    }

    private static func trianglePath(width: CGFloat, height: CGFloat) -> BodyTrendPlatformPath {
        #if os(iOS)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -width / 2, y: -height / 2))
        path.addLine(to: CGPoint(x: 0, y: height / 2))
        path.addLine(to: CGPoint(x: width / 2, y: -height / 2))
        path.close()
        return path
        #elseif os(macOS)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: -width / 2, y: -height / 2))
        path.line(to: NSPoint(x: 0, y: height / 2))
        path.line(to: NSPoint(x: width / 2, y: -height / 2))
        path.close()
        return path
        #else
        return BodyTrendPlatformPath()
        #endif
    }

    // MARK: - Palette and platform helpers

    private static func ribbonColor(_ mood: MoodLevel?, alpha: CGFloat = 1) -> BodyTrendPlatformColor {
        switch mood {
        case .excellent, .good: return color("A7D9C8", alpha: alpha)
        case .neutral: return color("B9A6E0", alpha: alpha)
        case .low, .veryLow: return color("EBA8BE", alpha: alpha)
        case nil: return color("B9A6E0", alpha: alpha)
        }
    }

    private static func moodColor(_ mood: MoodLevel?) -> BodyTrendPlatformColor {
        switch mood {
        case .excellent: return color("A9DCC8")
        case .good: return color("B8D8ED")
        case .neutral: return color("C8B8E7")
        case .low: return color("F0B0C3")
        case .veryLow: return color("E99AAA")
        case nil: return color("C8B8E7")
        }
    }

    private static func material(_ color: BodyTrendPlatformColor, roughness: CGFloat,
                                 metalness: CGFloat, clearCoat: CGFloat,
                                 emission: BodyTrendPlatformColor? = nil) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = roughness
        material.metalness.contents = metalness
        material.clearCoat.contents = clearCoat
        material.clearCoatRoughness.contents = 0.30
        if let emission { material.emission.contents = emission }
        material.specular.contents = BodyTrendPlatformColor.white.withAlphaComponent(0.28)
        return material
    }

    private static func color(_ hex: String, alpha: CGFloat = 1) -> BodyTrendPlatformColor {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)
        let red = CGFloat((number >> 16) & 0xff) / 255
        let green = CGFloat((number >> 8) & 0xff) / 255
        let blue = CGFloat(number & 0xff) / 255
        return BodyTrendPlatformColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(upper, max(lower, value))
    }

    private static func setZRotation(on node: SCNNode, value: Float) {
        #if os(macOS)
        node.eulerAngles.z = CGFloat(value)
        #else
        node.eulerAngles.z = value
        #endif
    }

    private static func setYRotation(on node: SCNNode, value: Float) {
        #if os(macOS)
        node.eulerAngles.y = CGFloat(value)
        #else
        node.eulerAngles.y = value
        #endif
    }
}
#endif
