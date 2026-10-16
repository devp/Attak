package club.attak.engines;

import android.app.Activity;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;

/**
 * Tells GDScript where Android installed the bundled engines.
 * See src/interfaces/BundledEngines.gd.
 */
public class AttakEngines extends GodotPlugin {
    public AttakEngines(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "AttakEngines";
    }

    /** The directory lib/<abi>/*.so from the APK were extracted to, or "" if unknown. */
    @UsedByGodot
    public String getNativeLibraryDir() {
        Activity activity = getActivity();
        if (activity == null) {
            return "";
        }
        String dir = activity.getApplicationInfo().nativeLibraryDir;
        return dir == null ? "" : dir;
    }

    /** Whether this process may execute the file (access(2) with X_OK). */
    @UsedByGodot
    public boolean canExecute(String path) {
        return new File(path).canExecute();
    }
}
