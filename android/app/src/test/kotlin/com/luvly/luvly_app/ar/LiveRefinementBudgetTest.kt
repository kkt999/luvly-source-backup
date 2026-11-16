package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test

class LiveRefinementBudgetTest {
    @Test fun requiresWarmupAndThreeConsecutiveExpensiveMasks() {
        val b=LiveRefinementBudget()
        repeat(4) { b.observe(100,100);assertTrue(b.enabled) }
        b.observe(100,100);assertFalse(b.enabled)
        b.observe(10,10);assertFalse(b.enabled)
    }
    @Test fun cheapMasksAndIsolatedSpikesDoNotDisableRefinement() {
        val b=LiveRefinementBudget()
        repeat(10) { b.observe(200,20) };assertTrue(b.enabled)
        repeat(4) { b.observe(100,100);b.observe(20,20) };assertTrue(b.enabled)
        repeat(10) { b.observe(20,70) };assertTrue(b.enabled)
        repeat(10) { b.observe(-1,200) };assertTrue(b.enabled)
    }
}
