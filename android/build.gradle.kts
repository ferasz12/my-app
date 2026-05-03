allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    // ننتظر حتى يتم تحميل خصائص الأندرويد في المكتبات الفرعية
    project.afterEvaluate {
        extensions.findByName("android")?.let { android ->
            val baseExtension = android as? com.android.build.gradle.BaseExtension
            // حل مشكلة الـ Namespace فقط إذا كان مفقوداً
            if (baseExtension?.namespace == null) {
                baseExtension?.namespace = "com.wazin.fix.${project.name.replace("-", "_")}"
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}