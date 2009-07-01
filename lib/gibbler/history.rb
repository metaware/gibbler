


module Gibbler
  class NoRevert < Gibbler::Error
    def message; "Revert not implemented for #{@obj}" end
  end
  class NoHistory < Gibbler::Error
    def message; "No history for #{@obj}"; end
  end
  class BadGibble < Gibbler::Error
    def message; "Unknown gibble: #{@obj}"; end
  end
    
  module History
    
    @@mutex = Mutex.new
    
    def self.mutex; @@mutex; end
    
    # Returns an Array of gibbles in the order they were committed. 
    def gibble_history
      # Only a single thread should attempt to initialize the store.
      if @__gibbles__.nil?
        @@mutex.synchronize {
          @__gibbles__ ||= { :order => [], :objects => {}, :stamp => {} }
        }
      end
      @__gibbles__[:order]
    end
    
    # Returns the object stored under the given gibble +g+.
    # If +g+ is not a valid gibble, returns nil. 
    def gibble_object(g) 
      return unless gibble_valid? g
      @__gibbles__[:objects][ g ]
    end
    
    # Returns the timestamp (a Time object) when the gibble +g+ was committed. 
    # If +g+ is not a valid gibble, returns nil. 
    def gibble_stamp(g)
      return unless gibble_valid? g
      @__gibbles__[:stamp][ g ]
    end
    
    # Stores a clone of the current object instance using the current
    # gibble value. If the object was not changed, this method does
    # nothing but return the gibble. 
    #
    # NOTE: This method is not fully thread safe. It uses a Mutex.synchronize
    # but there's a race condition where two threads can attempt to commit at 
    # near the same time. The first will get the lock and create the commit. 
    # The second will get the lock and create another commit immediately 
    # after. What we probably want is for the second thread to return the 
    # gibble for that first snapshot, but how do we know this was a result
    # of the race conditioon rather than two legitimate calls for a snapshot?
    def gibble_commit
      now, gibble, point = nil,nil,nil
      
      if @__gibbles__.nil?
        @@mutex.synchronize {
          @__gibbles__ ||= { :order => [], :objects => {}, :stamp => {} }
        }
      end
      
      @@mutex.synchronize {
        now, gibble, point = Time.now, self.gibble, self.clone
        @__gibbles__[:order] << gibble
        @__gibbles__[:stamp][now.to_i] = gibble
        @__gibbles__[:objects][gibble] = point
      }
      
      gibble
    end
    
    # Revert this object to a previously known state. If called without arguments
    # it will revert to the most recent commit. If a gibble is specified +g+, it
    # will revert to that point. 
    #
    # Ruby does not support replacing self (<tt>self = previous_self</tt>) so each 
    # object type needs to implement its own __gibble_revert method. This default
    # run some common checks and then defers to self.__gibble_revert. 
    # 
    # Raise the following exceptions:
    # * NoRevert: if this object doesn't have a __gibble_revert method
    # * NoHistory: This object has no commits
    # * BadGibble: The given gibble is not in the history for this object
    #
    # If +g+ matches the current gibble value this method does nothing. 
    #
    # Returns the new gibble (+g+). 
    def gibble_revert(g=nil)
      raise NoRevert unless self.respond_to?(:__gibble_revert)
      raise NoHistory, self.class unless gibble_history?
      g = self.gibble_history.last if g.nil?
      raise BadGibble, g unless gibble_valid? g
      
      # Do nothing if the given gibble matches the current gibble. 
      # NOTE: We use __gibbler b/c it doesn't update @@__gibble__.
      unless self.__gibbler == g
        @@mutex.synchronize {
          # Always make sure @__gibble__ is a Gibble. 
          @__gibble__ = g.is_a?(Gibble) ? g : Gibble.new(g)
          self.__gibble_revert
        }
      end
      
      @__gibble__
    end
    
    # Is the given gibble +g+ contained in the history for this object?
    def gibble_valid?(g)
      return false unless gibble_history?
      gibble_history.member? g
    end
    
    # Does the current object have any history?
    def gibble_history?
      !gibble_history.empty?
    end
    
  end
  
end

class Hash
  include Gibbler::History
  def __gibble_revert
    self.clear
    self.merge! self.gibble_object @__gibble__
  end
end

class Array
  include Gibbler::History
  def __gibble_revert
    self.clear
    self.push *(self.gibble_object @__gibble__)
  end
end
  
class String
  include Gibbler::History
  def __gibble_revert
    self.clear
    self << (self.gibble_object @__gibble__)
  end
end
      

