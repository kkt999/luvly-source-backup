package com.luvly.luvly_app.ar

/** Bounded local wrap articulation; not cloth physics. Independent left/right
 * offsets use the same validated world-pose pair as the torso. */
internal object SleeveFit {
    val neutral=Vec3(0f,0f,0f)
    fun offsets(pose: DressPose, world: List<WorldBodyPoint>, image: List<BodyPoint>): Pair<Vec3,Vec3> {
        val basis=pose.spatial ?: return neutral to neutral
        if(world.size<25 || image.size<25)return neutral to neutral
        val centre=(world[11].cameraVector()+world[12].cameraVector())*.5f
        var left=neutral;var right=neutral
        for(i in 11..12) {
            val elbow=i+2
            if(listOf(i,elbow).any { !world[it].confidence.isFinite() || world[it].confidence<.7f ||
                !image[it].confidence.isFinite() || image[it].confidence<.7f ||
                image[it].x !in 0f..1f || image[it].y !in 0f..1f })continue
            val shoulder=world[i].cameraVector();val arm=world[elbow].cameraVector()-shoulder
            if(!arm.finite() || arm.length() !in .12f.. .50f)continue
            val axis=arm.unit() ?: continue
            val side=if((shoulder-centre).dot(basis.right)<0f)-1f else 1f
            // This is an off-shoulder wrap attached across the bodice, not a
            // separate sleeve. Full elbow-follow stretches it into a long loop.
            // Allow small local slack redistribution; do not lift it above the shoulder.
            val dx=(axis.dot(basis.right)*.04f*side).coerceIn(-.025f,.04f)*side
            val dy=((axis.dot(basis.up)+1f)*.0275f).coerceIn(0f,.055f)
            val dz=(axis.dot(basis.forward)*.035f).coerceIn(-.035f,.035f)
            val value=Vec3(dx/.12f,dy/.22f,dz/.12f)
            if(side<0)left=value else right=value
        }
        return left to right
    }
}
