import JewelryKit
import SwiftUI

/// Renders the head slice without a 3D framework: the builder emits meshes and
/// this view projects them. Keeping the renderer dumb makes it easy to replace
/// with Metal/RealityKit later without touching the recovered geometry.
struct HeadPreviewView: View {
    let assembly: HeadAssembly
    @State private var yaw: Double = -0.6
    @State private var pitch: Double = 0.35
    @State private var dragStart: (yaw: Double, pitch: Double)?

    private struct Face {
        var depth: Double
        var points: [CGPoint]
        var color: Color
    }

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.11, blue: 0.13),
                         Color(red: 0.03, green: 0.03, blue: 0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .gesture(
            DragGesture()
                .onChanged { value in
                    if dragStart == nil { dragStart = (yaw, pitch) }
                    let start = dragStart ?? (yaw, pitch)
                    yaw = start.yaw + Double(value.translation.width) * 0.01
                    pitch = start.pitch - Double(value.translation.height) * 0.01
                }
                .onEnded { _ in dragStart = nil }
        )
        .accessibilityLabel("Parametric ring head preview")
        .accessibilityValue("\(assembly.prongs.count) prongs, \(assembly.triangleCount) triangles")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard let bounds = assembly.combined.bounds else { return }
        let center = Vec3(
            (bounds.min.x + bounds.max.x) / 2,
            (bounds.min.y + bounds.max.y) / 2,
            (bounds.min.z + bounds.max.z) / 2
        )
        let cosineYaw = cos(yaw)
        let sineYaw = sin(yaw)
        let cosinePitch = cos(pitch)
        let sinePitch = sin(pitch)

        func project(_ vertex: Vec3) -> (CGPoint, Double) {
            let x = vertex.x - center.x
            let y = vertex.y - center.y
            let z = vertex.z - center.z
            let x1 = x * cosineYaw - y * sineYaw
            let y1 = x * sineYaw + y * cosineYaw
            let y2 = y1 * cosinePitch - z * sinePitch
            let z2 = y1 * sinePitch + z * cosinePitch
            return (CGPoint(x: x1, y: -y2), z2)
        }

        var projected: [(CGPoint, Double)] = []
        projected.reserveCapacity(assembly.combined.vertices.count)
        for vertex in assembly.combined.vertices {
            projected.append(project(vertex))
        }

        let extent = projected.reduce(0.0) { partial, item in
            max(partial, max(abs(item.0.x), abs(item.0.y)))
        }
        guard extent > 1e-9 else { return }
        let scale = min(size.width, size.height) * 0.42 / extent
        let offset = CGPoint(x: size.width / 2, y: size.height / 2)

        func screen(_ point: CGPoint) -> CGPoint {
            CGPoint(x: offset.x + point.x * scale, y: offset.y + point.y * scale)
        }

        let light = Vec3(0.35, -0.45, 0.82).normalized()
        var faces: [Face] = []
        faces.reserveCapacity(assembly.combined.triangles.count)

        var vertexOffset = 0
        var meshes: [(Mesh3D, (Double, Double, Double))] = [(assembly.basket, (0.78, 0.62, 0.30))]
        meshes.append(contentsOf: assembly.prongs.map { ($0, (0.95, 0.78, 0.38)) })
        meshes.append(contentsOf: assembly.rails.map { ($0.mesh, (0.70, 0.54, 0.26)) })
        for (mesh, gold) in meshes {
            for triangle in mesh.triangles {
                let a = mesh.vertices[triangle.a]
                let b = mesh.vertices[triangle.b]
                let c = mesh.vertices[triangle.c]
                let normal = (b - a).cross(c - a).normalized()
                let shade = 0.32 + 0.68 * abs(normal.dot(light))
                let color = Color(
                    red: gold.0 * shade,
                    green: gold.1 * shade,
                    blue: gold.2 * shade
                )
                let pa = projected[triangle.a + vertexOffset]
                let pb = projected[triangle.b + vertexOffset]
                let pc = projected[triangle.c + vertexOffset]
                faces.append(Face(
                    depth: (pa.1 + pb.1 + pc.1) / 3,
                    points: [screen(pa.0), screen(pb.0), screen(pc.0)],
                    color: color
                ))
            }
            vertexOffset += mesh.vertices.count
        }

        faces.sort { $0.depth < $1.depth }
        for face in faces {
            var path = Path()
            path.addLines(face.points)
            path.closeSubpath()
            context.fill(path, with: .color(face.color))
            context.stroke(path, with: .color(.black.opacity(0.08)), lineWidth: 0.35)
        }
    }
}
