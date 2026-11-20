//! Per-thread allocation observation for zero-copy parser regression tests.
use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;

thread_local! {
    static ACTIVE: Cell<bool> = const { Cell::new(false) };
    static LARGEST: Cell<usize> = const { Cell::new(0) };
    static TOTAL: Cell<usize> = const { Cell::new(0) };
}

struct ObservedAllocator;

fn observe(size: usize) {
    let _ = ACTIVE.try_with(|active| {
        if active.get() {
            let _ = LARGEST.try_with(|largest| largest.set(largest.get().max(size)));
            let _ = TOTAL.try_with(|total| total.set(total.get().saturating_add(size)));
        }
    });
}

unsafe impl GlobalAlloc for ObservedAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        observe(layout.size());
        unsafe { System.alloc(layout) }
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        observe(layout.size());
        unsafe { System.alloc_zeroed(layout) }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        unsafe { System.dealloc(ptr, layout) }
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        observe(size);
        unsafe { System.realloc(ptr, layout, size) }
    }
}

#[global_allocator]
static ALLOCATOR: ObservedAllocator = ObservedAllocator;

pub(crate) fn largest_allocation<T>(operation: impl FnOnce() -> T) -> (T, usize) {
    struct Restore;
    impl Drop for Restore {
        fn drop(&mut self) {
            ACTIVE.with(|active| active.set(false));
        }
    }
    LARGEST.with(|largest| largest.set(0));
    TOTAL.with(|total| total.set(0));
    ACTIVE.with(|active| assert!(!active.replace(true), "nested allocation observation"));
    let guard = Restore;
    let result = operation();
    drop(guard);
    (result, LARGEST.with(Cell::get))
}

pub(crate) fn allocated_bytes<T>(operation: impl FnOnce() -> T) -> (T, usize) {
    let (result, _) = largest_allocation(operation);
    (result, TOTAL.with(Cell::get))
}
