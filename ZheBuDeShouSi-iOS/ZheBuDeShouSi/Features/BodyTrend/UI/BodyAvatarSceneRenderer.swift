import Foundation

#if canImport(SceneKit)
import Combine
import SceneKit

#if os(iOS)
import UIKit
private typealias BodyTrendPlatformColor = UIColor
private typealias BodyTrendPlatformImage = UIImage
#elseif os(macOS)
import AppKit
private typealias BodyTrendPlatformColor = NSColor
private typealias BodyTrendPlatformImage = NSImage
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

/// Builds the small, stylized 3D preview used by the body-trend workspace.
/// The geometry is a visual metaphor driven by measurements, not a scan or a
/// medical reconstruction.
enum BodyAvatarSceneRenderer {
    static func makeScene(
        snapshot: InBodySnapshot?,
        previousSnapshot: InBodySnapshot?,
        style: AvatarStyle,
        imageData: Data?
    ) -> SCNScene {
        let scene = SCNScene()
        // Soft candy palette keeps the 3D preview playful without becoming neon.
        scene.background.contents = color("FBF5FA")
        scene.lightingEnvironment.contents = color("F8EFF8")
        scene.lightingEnvironment.intensity = 0.28
        scene.fogColor = color("FBF5FA")
        scene.fogStartDistance = 8
        scene.fogEndDistance = 18

        let parameters = snapshot?.avatarParameters(relativeTo: previousSnapshot) ?? .neutral
        let width = Float(clamp(parameters.waistScale, lower: 0.78, upper: 1.25))
        let depth = Float(clamp(parameters.torsoScale, lower: 0.78, upper: 1.2))
        let height = Float(clamp(parameters.limbScale, lower: 0.9, upper: 1.12))

        let avatarRoot = SCNNode()
        switch style {
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
        // Lift the character onto the display plinth so rounded feet do not
        // visually sink into its top surface.
        avatarRoot.position = SCNVector3(0, 0.05, 0)
        setYRotation(on: avatarRoot, value: -0.12)
        scene.rootNode.addChildNode(avatarRoot)

        addBackdrop(to: scene, mood: snapshot?.mood)
        addStage(to: scene)
        addCamera(to: scene)
        addLights(to: scene)

        let bob = SCNAction.sequence([
            SCNAction.moveBy(x: 0, y: 0.018, z: 0, duration: 2.2),
            SCNAction.moveBy(x: 0, y: -0.018, z: 0, duration: 2.2)
        ])
        bob.timingMode = .easeInEaseOut
        avatarRoot.runAction(.repeatForever(bob), forKey: "gentle-bob")
        return scene
    }

    private static func addBackdrop(to scene: SCNScene, mood: MoodLevel?) {
        let panel = SCNPlane(width: 8, height: 6)
        panel.firstMaterial = material(color("FBF5FA"), roughness: 0.98, metalness: 0, clearCoat: 0)
        let panelNode = SCNNode(geometry: panel)
        panelNode.position = SCNVector3(0, 1.55, -1.35)
        scene.rootNode.addChildNode(panelNode)

        let glow = SCNPlane(width: 3.8, height: 3.55)
        glow.firstMaterial = material(
            ribbonColor(mood, alpha: 0.22),
            roughness: 0.94,
            metalness: 0,
            clearCoat: 0,
            emission: ribbonColor(mood, alpha: 0.04)
        )
        glow.firstMaterial?.transparency = 0.94
        let glowNode = SCNNode(geometry: glow)
        glowNode.position = SCNVector3(0, 1.45, -0.92)
        scene.rootNode.addChildNode(glowNode)

        addEditorialRibbon(to: scene, mood: mood)
    }

    private static func addEditorialRibbon(to scene: SCNScene, mood: MoodLevel?) {
        #if os(iOS)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -1.20, y: -0.92))
        path.addCurve(
            to: CGPoint(x: 0.92, y: 0.78),
            controlPoint1: CGPoint(x: -0.50, y: -0.66),
            controlPoint2: CGPoint(x: 0.28, y: 0.56)
        )
        path.addCurve(
            to: CGPoint(x: 0.82, y: 0.91),
            controlPoint1: CGPoint(x: 0.90, y: 0.83),
            controlPoint2: CGPoint(x: 0.86, y: 0.88)
        )
        path.addCurve(
            to: CGPoint(x: -1.15, y: -0.82),
            controlPoint1: CGPoint(x: 0.18, y: 0.65),
            controlPoint2: CGPoint(x: -0.64, y: -0.48)
        )
        path.close()
        #elseif os(macOS)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: -1.20, y: -0.92))
        path.curve(
            to: NSPoint(x: 0.92, y: 0.78),
            controlPoint1: NSPoint(x: -0.50, y: -0.66),
            controlPoint2: NSPoint(x: 0.28, y: 0.56)
        )
        path.curve(
            to: NSPoint(x: 0.82, y: 0.91),
            controlPoint1: NSPoint(x: 0.90, y: 0.83),
            controlPoint2: NSPoint(x: 0.86, y: 0.88)
        )
        path.curve(
            to: NSPoint(x: -1.15, y: -0.82),
            controlPoint1: NSPoint(x: 0.18, y: 0.65),
            controlPoint2: NSPoint(x: -0.64, y: -0.48)
        )
        path.close()
        #else
        return
        #endif

        let ribbon = SCNShape(path: path, extrusionDepth: 0.012)
        ribbon.chamferRadius = 0.004
        ribbon.firstMaterial = material(
            ribbonColor(mood, alpha: 0.26),
            roughness: 0.82,
            metalness: 0,
            clearCoat: 0.04,
            emission: ribbonColor(mood, alpha: 0.02)
        )
        let ribbonNode = SCNNode(geometry: ribbon)
        ribbonNode.position = SCNVector3(-0.62, 1.18, -0.76)
        setZRotation(on: ribbonNode, value: -0.08)
        scene.rootNode.addChildNode(ribbonNode)
    }

    private static func ribbonColor(_ mood: MoodLevel?, alpha: CGFloat = 1) -> BodyTrendPlatformColor {
        switch mood {
        case .excellent, .good:
            return color("9FD9C1", alpha: alpha)
        case .neutral:
            return color("C8B4E8", alpha: alpha)
        case .low, .veryLow:
            return color("F3A6B9", alpha: alpha)
        case nil:
            return color("C8B4E8", alpha: alpha)
        }
    }

    private static func addStage(to scene: SCNScene) {
        let floor = SCNFloor()
        floor.reflectivity = 0.14
        floor.firstMaterial = material(color("F3EAF3"), roughness: 0.86, metalness: 0, clearCoat: 0.04)
        let floorNode = SCNNode(geometry: floor)
        floorNode.position.y = -0.31
        floorNode.opacity = 0.92
        scene.rootNode.addChildNode(floorNode)

        let platform = SCNCylinder(radius: 1.38, height: 0.085)
        platform.radialSegmentCount = 96
        platform.firstMaterial = material(color("FFF9FD"), roughness: 0.56, metalness: 0.02, clearCoat: 0.16)
        let platformNode = SCNNode(geometry: platform)
        platformNode.position.y = -0.27
        scene.rootNode.addChildNode(platformNode)

        let inset = SCNCylinder(radius: 1.20, height: 0.018)
        inset.radialSegmentCount = 96
        inset.firstMaterial = material(color("F0E8F6"), roughness: 0.62, metalness: 0.01, clearCoat: 0.08)
        let insetNode = SCNNode(geometry: inset)
        insetNode.position.y = -0.215
        scene.rootNode.addChildNode(insetNode)

        let ring = SCNTorus(ringRadius: 1.12, pipeRadius: 0.022)
        ring.ringSegmentCount = 96
        ring.pipeSegmentCount = 16
        ring.firstMaterial = material(
            color("D2A9DF"),
            roughness: 0.42,
            metalness: 0.06,
            clearCoat: 0.18,
            emission: color("EBD4F0", alpha: 0.06)
        )
        let ringNode = SCNNode(geometry: ring)
        ringNode.position.y = -0.195
        scene.rootNode.addChildNode(ringNode)

        let halo = SCNTorus(ringRadius: 1.13, pipeRadius: 0.018)
        halo.ringSegmentCount = 96
        halo.pipeSegmentCount = 12
        halo.firstMaterial = material(
            color("F2A9C5", alpha: 0.46),
            roughness: 0.5,
            metalness: 0.02,
            clearCoat: 0.12,
            emission: color("F9D4E6", alpha: 0.06)
        )
        let haloNode = SCNNode(geometry: halo)
        haloNode.position = SCNVector3(0, 1.35, -0.46)
        haloNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        haloNode.scale = SCNVector3(1, 1.08, 1)
        scene.rootNode.addChildNode(haloNode)
    }

    private static func addCamera(to scene: SCNScene) {
        let targetNode = SCNNode()
        targetNode.position = SCNVector3(0, 1.08, 0)
        scene.rootNode.addChildNode(targetNode)

        let camera = SCNCamera()
        // Leave a little breathing room for the tall hair silhouette while
        // keeping the face large enough to read in the compact card.
        camera.fieldOfView = 38
        camera.zNear = 0.05
        camera.zFar = 50
        camera.automaticallyAdjustsZRange = true
        camera.wantsHDR = true
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 1.15, 4.65)
        cameraNode.constraints = [SCNLookAtConstraint(target: targetNode)]
        scene.rootNode.addChildNode(cameraNode)
    }

    private static func addLights(to scene: SCNScene) {
        let keyLight = SCNLight()
        keyLight.type = .area
        keyLight.intensity = 620
        keyLight.color = color("FFF9FC")
        keyLight.castsShadow = true
        keyLight.shadowRadius = 12
        keyLight.shadowColor = color("8E647A", alpha: 0.18)
        #if os(macOS)
        // The preview is small; a 512px map keeps timeline scrubbing light.
        keyLight.shadowMapSize = CGSize(width: 512, height: 512)
        keyLight.shadowSampleCount = 8
        #endif
        let keyNode = SCNNode()
        keyNode.light = keyLight
        keyNode.position = SCNVector3(2.4, 3.5, 4.1)
        keyNode.eulerAngles = SCNVector3(-0.54, 0.38, 0)
        scene.rootNode.addChildNode(keyNode)

        let fillLight = SCNLight()
        fillLight.type = .omni
        fillLight.intensity = 320
        fillLight.color = color("DCEEFF")
        let fillNode = SCNNode()
        fillNode.light = fillLight
        fillNode.position = SCNVector3(-2.2, 2.1, 2.5)
        scene.rootNode.addChildNode(fillNode)

        let rimLight = SCNLight()
        rimLight.type = .omni
        rimLight.intensity = 300
        rimLight.color = color("F7C8DF")
        let rimNode = SCNNode()
        rimNode.light = rimLight
        rimNode.position = SCNVector3(0.3, 2.6, -2.7)
        scene.rootNode.addChildNode(rimNode)

        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 105
        ambientLight.color = color("FFF5FA")
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
    }

    private enum AnimalKind {
        case cat
        case dog
    }

    private static func addHuman(to root: SCNNode, width: Float, depth: Float, height: Float, mood: MoodLevel?) {
        // Refined chibi proportions keep the face expressive without making it
        // dwarf the body; measured width/depth still shape the silhouette.
        let outfit = material(moodColor(mood), roughness: 0.48, metalness: 0.01, clearCoat: 0.24)
        let skin = material(color("FFE0D2"), roughness: 0.64, metalness: 0, clearCoat: 0.08)
        let hair = material(color("E9A9C5"), roughness: 0.52, metalness: 0.01, clearCoat: 0.12)
        let accent = material(color("F6B8CF"), roughness: 0.44, metalness: 0.01, clearCoat: 0.2)

        let torso = SCNCapsule(capRadius: 0.38, height: 0.96)
        torso.radialSegmentCount = 48
        torso.firstMaterial = outfit
        let torsoNode = SCNNode(geometry: torso)
        torsoNode.scale = SCNVector3(width * 0.92, height * 0.94, depth * 0.82)
        torsoNode.position = SCNVector3(0, 0.82, 0)
        root.addChildNode(torsoNode)

        let skirt = SCNCapsule(capRadius: 0.33, height: 0.66)
        skirt.radialSegmentCount = 40
        skirt.firstMaterial = outfit
        let skirtNode = SCNNode(geometry: skirt)
        skirtNode.scale = SCNVector3(width * 1.04, 0.72 * height, depth * 0.88)
        skirtNode.position = SCNVector3(0, 0.48, 0)
        root.addChildNode(skirtNode)

        addLimb(to: root, position: SCNVector3(-0.39 * width, 0.86, 0), radius: 0.115, length: 0.52 * height, material: outfit, rotation: -0.13)
        addLimb(to: root, position: SCNVector3(0.39 * width, 0.86, 0), radius: 0.115, length: 0.52 * height, material: outfit, rotation: 0.13)
        addLimb(to: root, position: SCNVector3(-0.15 * width, 0.18, 0), radius: 0.13, length: 0.64 * height, material: skin, rotation: 0)
        addLimb(to: root, position: SCNVector3(0.15 * width, 0.18, 0), radius: 0.13, length: 0.64 * height, material: skin, rotation: 0)
        addHandOrFoot(to: root, position: SCNVector3(-0.45 * width, 0.54, 0.04), scale: SCNVector3(1.02, 0.88, 0.88), material: skin)
        addHandOrFoot(to: root, position: SCNVector3(0.45 * width, 0.54, 0.04), scale: SCNVector3(1.02, 0.88, 0.88), material: skin)
        addHandOrFoot(to: root, position: SCNVector3(-0.17 * width, -0.20, 0.10), scale: SCNVector3(1.25, 0.54, 1.55), material: accent)
        addHandOrFoot(to: root, position: SCNVector3(0.17 * width, -0.20, 0.10), scale: SCNVector3(1.25, 0.54, 1.55), material: accent)

        let neck = SCNCylinder(radius: 0.15, height: 0.16)
        neck.radialSegmentCount = 32
        neck.firstMaterial = skin
        let neckNode = SCNNode(geometry: neck)
        neckNode.position = SCNVector3(0, 1.30, 0)
        root.addChildNode(neckNode)

        let head = SCNSphere(radius: 0.52)
        head.segmentCount = 56
        head.firstMaterial = skin
        let headNode = SCNNode(geometry: head)
        headNode.scale = SCNVector3(width * 0.99, height * 1.00, depth * 0.98)
        headNode.position = SCNVector3(0, 1.67, 0)
        root.addChildNode(headNode)

        let hairCap = SCNSphere(radius: 0.55)
        hairCap.segmentCount = 56
        hairCap.firstMaterial = hair
        let hairNode = SCNNode(geometry: hairCap)
        hairNode.scale = SCNVector3(width * 1.01, height * 0.68, depth * 1.00)
        hairNode.position = SCNVector3(0, 1.84, -0.035)
        root.addChildNode(hairNode)

        for index in -1...1 {
            let strand = SCNCapsule(capRadius: 0.070, height: 0.34)
            strand.radialSegmentCount = 28
            strand.firstMaterial = hair
            let strandNode = SCNNode(geometry: strand)
            strandNode.position = SCNVector3(Float(index) * 0.18 * width, 1.73 + (index == 0 ? 0.025 : 0), 0.40 * depth)
            strandNode.scale = SCNVector3(0.82, 1.0 + (index == 0 ? 0.06 : 0), 0.38)
            setZRotation(on: strandNode, value: Float(index) * 0.06)
            root.addChildNode(strandNode)
        }

        // Twin side locks and a small bow make the silhouette feel intentional.
        for side: Float in [-1, 1] {
            let lock = SCNCapsule(capRadius: 0.078, height: 0.46)
            lock.radialSegmentCount = 28
            lock.firstMaterial = hair
            let lockNode = SCNNode(geometry: lock)
            lockNode.position = SCNVector3(side * 0.38 * width, 1.53, 0.20 * depth)
            lockNode.scale = SCNVector3(0.86, 1.0, 0.44)
            setZRotation(on: lockNode, value: side * -0.15)
            root.addChildNode(lockNode)
        }
        addBow(to: root, position: SCNVector3(0.36 * width, 2.04, 0.03), material: accent, scale: 0.56)
        addFace(to: root, y: 1.67, faceWidth: width, faceDepth: depth, mood: mood)
    }

    private static func addAnimal(to root: SCNNode, kind: AnimalKind, width: Float, depth: Float, height: Float, mood: MoodLevel?) {
        let furColor = kind == .cat ? color("C9B9D9") : color("E5BFA9")
        let fur = material(furColor, roughness: 0.72, metalness: 0, clearCoat: 0.08)
        let belly = material(kind == .cat ? color("F1E8F2") : color("FFE5D3"), roughness: 0.76, metalness: 0, clearCoat: 0.06)
        let accent = material(kind == .cat ? color("F3A9C6") : color("A9CBE3"), roughness: 0.46, metalness: 0.01, clearCoat: 0.18)

        let body = SCNSphere(radius: 0.70)
        body.segmentCount = 48
        body.firstMaterial = fur
        let bodyNode = SCNNode(geometry: body)
        bodyNode.scale = SCNVector3(0.96 * width, 0.68 * height, 0.78 * depth)
        bodyNode.position = SCNVector3(0, 0.72, 0)
        root.addChildNode(bodyNode)

        let bellyPatch = SCNSphere(radius: 0.52)
        bellyPatch.segmentCount = 40
        bellyPatch.firstMaterial = belly
        let bellyNode = SCNNode(geometry: bellyPatch)
        bellyNode.scale = SCNVector3(0.70 * width, 0.74 * height, 0.26 * depth)
        bellyNode.position = SCNVector3(0, 0.72, 0.52)
        root.addChildNode(bellyNode)

        for side: Float in [-1, 1] {
            addLimb(
                to: root,
                position: SCNVector3(side * 0.33 * width, 0.02, 0.04),
                radius: 0.13,
                length: 0.38 * height,
                material: fur,
                rotation: 0
            )
            addHandOrFoot(
                to: root,
                position: SCNVector3(side * 0.33 * width, -0.20, 0.09),
                scale: SCNVector3(0.84, 0.62 * height, 0.88),
                material: fur
            )
        }

        let head = SCNSphere(radius: 0.55)
        head.segmentCount = 48
        head.firstMaterial = fur
        let headNode = SCNNode(geometry: head)
        headNode.scale = SCNVector3(width * 0.98, height * 0.98, depth * 0.98)
        headNode.position = SCNVector3(0, 1.50, 0)
        root.addChildNode(headNode)

        if kind == .cat {
            let ear = SCNCone(topRadius: 0.01, bottomRadius: 0.19, height: 0.34)
            ear.radialSegmentCount = 32
            ear.firstMaterial = fur
            for side: Float in [-1, 1] {
                let earNode = SCNNode(geometry: ear)
                earNode.position = SCNVector3(side * 0.36 * width, 1.93, 0)
                setZRotation(on: earNode, value: side * -0.16)
                root.addChildNode(earNode)
            }
        } else {
            for side: Float in [-1, 1] {
                let ear = SCNSphere(radius: 0.19)
                ear.firstMaterial = fur
                let earNode = SCNNode(geometry: ear)
                earNode.scale = SCNVector3(0.62, 1.25, 0.44)
                earNode.position = SCNVector3(side * 0.42 * width, 1.53, -0.01)
                root.addChildNode(earNode)
            }
        }

        let muzzle = SCNSphere(radius: 0.19)
        muzzle.firstMaterial = belly
        let muzzleNode = SCNNode(geometry: muzzle)
        muzzleNode.scale = SCNVector3(1.18, 0.72, 0.60)
        muzzleNode.position = SCNVector3(0, 1.41, 0.44)
        root.addChildNode(muzzleNode)

        let collar = SCNTorus(ringRadius: 0.30, pipeRadius: 0.028)
        collar.ringSegmentCount = 64
        collar.pipeSegmentCount = 12
        collar.firstMaterial = accent
        let collarNode = SCNNode(geometry: collar)
        collarNode.scale = SCNVector3(width, 1, depth)
        collarNode.position = SCNVector3(0, 1.24, 0)
        root.addChildNode(collarNode)

        let charm = SCNSphere(radius: 0.055)
        charm.firstMaterial = material(color("FFF6FB"), roughness: 0.25, metalness: 0.18, clearCoat: 0.5)
        let charmNode = SCNNode(geometry: charm)
        charmNode.position = SCNVector3(0, 1.21, 0.30)
        root.addChildNode(charmNode)

        let tail = SCNTorus(ringRadius: 0.27, pipeRadius: 0.075)
        tail.ringSegmentCount = 64
        tail.pipeSegmentCount = 16
        tail.firstMaterial = fur
        let tailNode = SCNNode(geometry: tail)
        tailNode.position = SCNVector3(0.60 * width, 0.68, -0.10)
        tailNode.eulerAngles = SCNVector3(0.2, 0.1, 0.75)
        root.addChildNode(tailNode)

        addBow(to: root, position: SCNVector3(-0.38 * width, 1.89, 0.03), material: accent, scale: 0.54)
        addAnimalFace(to: root, y: 1.50, faceWidth: width, kind: kind, mood: mood)
    }

    private static func addPhoto(to root: SCNNode, image: BodyTrendPlatformImage, width: Float, height: Float) {
        let cardWidth = CGFloat(1.32 * width)
        let cardHeight = CGFloat(2.16 * height)

        let backing = SCNBox(width: cardWidth + 0.12, height: cardHeight + 0.12, length: 0.08, chamferRadius: 0.12)
        backing.firstMaterial = material(color("D8E4E4"), roughness: 0.58, metalness: 0.02, clearCoat: 0.12)
        let backingNode = SCNNode(geometry: backing)
        backingNode.position = SCNVector3(0, 1.10, -0.07)
        root.addChildNode(backingNode)

        let plane = SCNPlane(width: cardWidth, height: cardHeight)
        let photoMaterial = SCNMaterial()
        photoMaterial.lightingModel = .constant
        photoMaterial.diffuse.contents = image
        photoMaterial.isDoubleSided = true
        plane.firstMaterial = photoMaterial
        let photoNode = SCNNode(geometry: plane)
        photoNode.position = SCNVector3(0, 1.10, 0.015)
        setYRotation(on: photoNode, value: 0.05)
        root.addChildNode(photoNode)

        let frameMaterial = material(color("F8F5EF"), roughness: 0.42, metalness: 0.04, clearCoat: 0.18)
        let frameThickness: CGFloat = 0.045
        let top = SCNBox(width: cardWidth + 0.08, height: frameThickness, length: 0.12, chamferRadius: 0.018)
        let side = SCNBox(width: frameThickness, height: cardHeight + 0.08, length: 0.12, chamferRadius: 0.018)
        top.firstMaterial = frameMaterial
        side.firstMaterial = frameMaterial
        let topNode = SCNNode(geometry: top)
        topNode.position = SCNVector3(0, 1.10 + Float(cardHeight / 2) + Float(frameThickness / 2), 0.04)
        root.addChildNode(topNode)
        let bottomNode = topNode.clone()
        bottomNode.position = SCNVector3(0, 1.10 - Float(cardHeight / 2) - Float(frameThickness / 2), 0.04)
        root.addChildNode(bottomNode)
        let leftNode = SCNNode(geometry: side)
        leftNode.position = SCNVector3(-Float(cardWidth / 2) - Float(frameThickness / 2), 1.10, 0.04)
        root.addChildNode(leftNode)
        let rightNode = leftNode.clone()
        rightNode.position = SCNVector3(Float(cardWidth / 2) + Float(frameThickness / 2), 1.10, 0.04)
        root.addChildNode(rightNode)
    }

    private static func addLimb(to root: SCNNode, position: SCNVector3, radius: CGFloat, length: Float, material: SCNMaterial, rotation: Float) {
        let geometry = SCNCapsule(capRadius: radius, height: CGFloat(length))
        geometry.radialSegmentCount = 32
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.position = position
        setZRotation(on: node, value: rotation)
        root.addChildNode(node)
    }

    private static func addHandOrFoot(to root: SCNNode, position: SCNVector3, scale: SCNVector3, material: SCNMaterial) {
        let geometry = SCNSphere(radius: 0.12)
        geometry.segmentCount = 32
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.position = position
        node.scale = scale
        root.addChildNode(node)
    }

    private static func addBow(to root: SCNNode, position: SCNVector3, material: SCNMaterial, scale: Float) {
        let left = SCNSphere(radius: 0.13)
        left.segmentCount = 32
        left.firstMaterial = material
        let leftNode = SCNNode(geometry: left)
        leftNode.position = position
        #if os(macOS)
        leftNode.position.x -= CGFloat(0.11 * scale)
        #else
        leftNode.position.x -= 0.11 * scale
        #endif
        leftNode.scale = SCNVector3(1.25 * scale, 0.78 * scale, 0.38 * scale)
        setZRotation(on: leftNode, value: -0.25)
        root.addChildNode(leftNode)

        let rightNode = leftNode.clone()
        rightNode.position = position
        #if os(macOS)
        rightNode.position.x += CGFloat(0.11 * scale)
        #else
        rightNode.position.x += 0.11 * scale
        #endif
        setZRotation(on: rightNode, value: 0.25)
        root.addChildNode(rightNode)

        let center = SCNSphere(radius: 0.075)
        center.segmentCount = 28
        center.firstMaterial = material
        let centerNode = SCNNode(geometry: center)
        centerNode.position = position
        centerNode.scale = SCNVector3(scale, scale, scale)
        root.addChildNode(centerNode)
    }

    private static func addFace(to root: SCNNode, y: Float, faceWidth: Float, faceDepth: Float, mood: MoodLevel?) {
        let eyeWhite = material(color("FBFAF6"), roughness: 0.30, metalness: 0, clearCoat: 0.24)
        let eyeDark = material(color("674B6F"), roughness: 0.30, metalness: 0, clearCoat: 0.32)
        let cheek = material(color("F49ABB", alpha: 0.48), roughness: 0.48, metalness: 0, clearCoat: 0.10)

        for side: Float in [-1, 1] {
            let white = SCNSphere(radius: 0.086)
            white.segmentCount = 32
            white.firstMaterial = eyeWhite
            let whiteNode = SCNNode(geometry: white)
            whiteNode.scale = SCNVector3(0.84, 1.16, 0.52)
            whiteNode.position = SCNVector3(side * 0.18 * faceWidth, y + 0.015, 0.47 * faceDepth)
            root.addChildNode(whiteNode)

            let pupil = SCNSphere(radius: 0.045)
            pupil.segmentCount = 24
            pupil.firstMaterial = eyeDark
            let pupilNode = SCNNode(geometry: pupil)
            pupilNode.position = SCNVector3(side * 0.18 * faceWidth, y + 0.01, 0.535 * faceDepth)
            root.addChildNode(pupilNode)

            let highlight = SCNSphere(radius: 0.013)
            highlight.firstMaterial = material(color("FFFFFF"), roughness: 0.22, metalness: 0, clearCoat: 0.32)
            let highlightNode = SCNNode(geometry: highlight)
            highlightNode.position = SCNVector3(side * 0.16 * faceWidth, y + 0.048, 0.58 * faceDepth)
            root.addChildNode(highlightNode)

            let cheekNode = SCNNode(geometry: SCNSphere(radius: 0.058))
            cheekNode.geometry?.firstMaterial = cheek
            cheekNode.scale = SCNVector3(1.18, 0.46, 0.16)
            cheekNode.position = SCNVector3(side * 0.27 * faceWidth, y - 0.125, 0.46 * faceDepth)
            root.addChildNode(cheekNode)
        }

        let mouth = SCNTorus(ringRadius: mood == .veryLow || mood == .low ? 0.052 : 0.038, pipeRadius: 0.011)
        mouth.ringSegmentCount = 40
        mouth.pipeSegmentCount = 10
        mouth.firstMaterial = material(color("A85E7D"), roughness: 0.44, metalness: 0, clearCoat: 0.14)
        let mouthNode = SCNNode(geometry: mouth)
        mouthNode.scale = SCNVector3(1.08, mood == .veryLow || mood == .low ? 0.38 : 0.48, 0.32)
        mouthNode.position = SCNVector3(0, y - 0.16, 0.50 * faceDepth)
        root.addChildNode(mouthNode)
    }

    private static func addAnimalFace(to root: SCNNode, y: Float, faceWidth: Float, kind: AnimalKind, mood: MoodLevel?) {
        let eye = material(color("674B6F"), roughness: 0.26, metalness: 0, clearCoat: 0.34)
        for side: Float in [-1, 1] {
            let eyeGeometry = SCNSphere(radius: 0.074)
            eyeGeometry.segmentCount = 28
            eyeGeometry.firstMaterial = eye
            let eyeNode = SCNNode(geometry: eyeGeometry)
            eyeNode.position = SCNVector3(side * 0.20 * faceWidth, y + 0.025, 0.52)
            root.addChildNode(eyeNode)

            let highlight = SCNSphere(radius: 0.017)
            highlight.firstMaterial = material(color("FFFFFF"), roughness: 0.22, metalness: 0, clearCoat: 0.32)
            let highlightNode = SCNNode(geometry: highlight)
            highlightNode.position = SCNVector3(side * 0.17 * faceWidth, y + 0.06, 0.59)
            root.addChildNode(highlightNode)

            let cheek = SCNSphere(radius: 0.057)
            cheek.segmentCount = 24
            cheek.firstMaterial = material(color("F49ABB", alpha: 0.46), roughness: 0.48, metalness: 0, clearCoat: 0.08)
            let cheekNode = SCNNode(geometry: cheek)
            cheekNode.position = SCNVector3(side * 0.30 * faceWidth, y - 0.12, 0.49)
            cheekNode.scale = SCNVector3(1.12, 0.44, 0.14)
            root.addChildNode(cheekNode)
        }

        let nose = SCNSphere(radius: kind == .cat ? 0.038 : 0.052)
        nose.firstMaterial = material(kind == .cat ? color("A67582") : color("6D625A"), roughness: 0.34, metalness: 0, clearCoat: 0.18)
        let noseNode = SCNNode(geometry: nose)
        noseNode.scale = SCNVector3(1.18, 0.76, 0.65)
        noseNode.position = SCNVector3(0, y - 0.09, 0.56)
        root.addChildNode(noseNode)

        let mouth = SCNTorus(ringRadius: mood == .veryLow || mood == .low ? 0.05 : 0.036, pipeRadius: 0.012)
        mouth.firstMaterial = material(color("9E607B"), roughness: 0.44, metalness: 0, clearCoat: 0.12)
        let mouthNode = SCNNode(geometry: mouth)
        mouthNode.scale = SCNVector3(1.35, 0.48, 0.42)
        mouthNode.position = SCNVector3(0, y - 0.15, 0.55)
        root.addChildNode(mouthNode)
    }

    private static func material(
        _ color: BodyTrendPlatformColor,
        roughness: CGFloat,
        metalness: CGFloat,
        clearCoat: CGFloat,
        emission: BodyTrendPlatformColor? = nil
    ) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = roughness
        material.metalness.contents = metalness
        material.clearCoat.contents = clearCoat
        material.clearCoatRoughness.contents = 0.28
        if let emission {
            material.emission.contents = emission
        }
        material.specular.contents = BodyTrendPlatformColor.white.withAlphaComponent(0.25)
        return material
    }

    private static func moodColor(_ mood: MoodLevel?) -> BodyTrendPlatformColor {
        switch mood {
        case .excellent, .good: return color("9FD9C1")
        case .neutral: return color("C8B4E8")
        case .low, .veryLow: return color("F3A6B9")
        case nil: return color("C8B4E8")
        }
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
