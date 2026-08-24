package me.osholt.balloon_crumbs

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidAutoCompanionTest {
    @After
    fun cleanUp() {
        AndroidAutoSnapshotStore.clearForTesting()
    }

    @Test
    fun `snapshot parser bounds untrusted phone data`() {
        val snapshot = ProjectedRideSnapshot.from(
            mapOf(
                "routeName" to " Balloon recovery ",
                "rideState" to "Flight in progress",
                "guidanceTitle" to "At the roundabout take exit 3",
                "guidanceDetail" to "400 m",
                "groupStatus" to "5 crew visible",
                "markerStatus" to "Landing area updated",
                "riders" to listOf(
                    mapOf(
                        "label" to "Charlie",
                        "role" to "Chase crew",
                        "needsAttention" to true,
                    ),
                ),
                "alert" to mapOf("message" to "Crew need assistance", "severity" to "urgent"),
                "updatedAtMillis" to 123L,
            ),
        )

        assertEquals("Balloon recovery", snapshot.routeName)
        assertEquals("At the roundabout take exit 3", snapshot.guidanceTitle)
        assertEquals("Landing area updated", snapshot.markerStatus)
        assertEquals(1, snapshot.riders.size)
        assertTrue(snapshot.riders.single().needsAttention)
        assertEquals("Crew need assistance", snapshot.alert?.message)
        assertEquals(123L, snapshot.updatedAtMillis)
    }

    @Test
    fun `snapshot parser supplies safe empty state`() {
        val snapshot = ProjectedRideSnapshot.from(emptyMap())

        assertNull(snapshot.routeName)
        assertEquals("Open the phone app", snapshot.rideState)
        assertEquals("0 crew visible", snapshot.groupStatus)
        assertTrue(snapshot.riders.isEmpty())
        assertNull(snapshot.alert)
    }

    @Test
    fun `snapshot store updates listeners and retains latest in process`() {
        var notified = false
        val listener = AndroidAutoSnapshotStore.Listener { notified = true }
        AndroidAutoSnapshotStore.addListener(listener)

        AndroidAutoSnapshotStore.update(mapOf("rideState" to "Flight paused"))

        assertTrue(notified)
        assertEquals("Flight paused", AndroidAutoSnapshotStore.latest?.rideState)
        AndroidAutoSnapshotStore.removeListener(listener)
        notified = false
        AndroidAutoSnapshotStore.update(mapOf("rideState" to "Flight ended"))
        assertFalse(notified)
    }
}
